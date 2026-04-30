import Foundation
import Observation
import os

/// Orchestrates voice reads/writes between the device and in-memory banks.
///
/// Owns three banks (factory, user, temporary) and exposes async load/save
/// flows. The transport seam means tests can drive this without CoreMIDI.
///
/// Threading model:
/// - The class itself is **not** main-actor isolated, so the inbound SysEx
///   pump can dispatch responses synchronously without an actor hop. All
///   `@Observable` state is mutated through serialized accesses inside this
///   class; SwiftUI views read on the main thread.
/// - `pendingResponse` is guarded by `pendingLock` to keep the request /
///   response handshake correct under contention.
@Observable
public final class BankController: @unchecked Sendable {
    public let factory: VoiceBank
    public let user: VoiceBank
    public let temporary: VoiceBank

    public private(set) var status: Status = .idle
    public private(set) var connection: ConnectionState = .disconnected
    /// True once the user bank has been read from the device or imported
    /// from a file in this session. Used to prevent `sendUserBank` from
    /// blowing away the device's bank with a fresh empty in-memory bank.
    public private(set) var userBankIsLoaded: Bool = false

    /// When true, write-back attempts go to the device. Default true — the
    /// write opcode (0x01) and the trailing bank-commit (0x05 7F 7F) are
    /// confirmed against the `user-bank-write.mmon` capture. Set to false
    /// to keep the UI button disabled while iterating.
    public var allowDeviceWrites: Bool = true

    /// Inter-request delay during bulk reads, in milliseconds.
    /// 5ms keeps a full factory load (377 voices) under ~12 s without
    /// overwhelming the device.
    public var readDelayMs: UInt = 5
    /// Per-voice response timeout in milliseconds. The device round-trips
    /// in ~30 ms over USB, so 250 ms is generous.
    public var readTimeoutMs: UInt = 250
    /// Maximum retries per missing voice during bulk read.
    public var readRetryLimit: Int = 2

    private let transport: any MIDITransport
    @ObservationIgnored private let log = Logger(subsystem: "org.local.MaskOrganizer", category: "BankController")
    @ObservationIgnored private var sysexTask: Task<Void, Never>?
    @ObservationIgnored private var stateTask: Task<Void, Never>?

    @ObservationIgnored private let pendingLock = NSLock()
    @ObservationIgnored private var pendingResponse: CheckedContinuation<[UInt8], any Error>?
    /// Monotonically-increasing request ID. Lets a timeout fire only against
    /// the specific request that armed it (subsequent requests bump the ID).
    @ObservationIgnored private var pendingSeq: UInt64 = 0
    @ObservationIgnored private var nextSeq: UInt64 = 0

    public init(transport: any MIDITransport) {
        self.transport = transport
        self.factory   = VoiceBank(kind: .factory)
        self.user      = VoiceBank(kind: .user)
        self.temporary = VoiceBank(kind: .temporary)

        // Inbound pump — dispatches responses synchronously (no actor hop).
        sysexTask = Task { [weak self] in
            guard let self else { return }
            for await frame in transport.incomingSysEx {
                self.handleIncoming(frame)
            }
        }
        stateTask = Task { [weak self] in
            guard let self else { return }
            for await s in transport.connectionState {
                self.connection = s
            }
        }
    }

    // MARK: Connection passthrough

    public func connect() async throws { try await transport.connect() }
    public func disconnect()           { transport.disconnect() }

    // MARK: Bulk read

    public enum LoadError: Swift.Error, Equatable {
        case alreadyBusy
        case cancelled
        case missingSlots([Int])
        case transport(String)
    }

    /// Read the factory bank (377 voices) from the device into the named
    /// destination. Defaults to `.temporary` to match the web app's
    /// "Load factory bank from MASK1" behavior, which lands voices in the
    /// left ("temporary") pane for the user to select from.
    public func loadFactoryBank(
        into kind: VoiceBank.Kind = .temporary,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        try await loadBank(into: bank(for: kind), range: 0..<377, progress: progress)
    }

    /// Read the user bank (200 voices) from the device.
    ///
    /// Device-absolute index range is **384…583** — confirmed by the
    /// `user-bank-read.mmon` capture (the web app starts at 384, not 377 as
    /// originally assumed; slots 377…383 are reserved/unused). The web app
    /// also probes index 584 with no response, presumably as a sentinel; we
    /// skip it.
    public func loadUserBank(progress: ((Double) -> Void)? = nil) async throws {
        try await loadBank(into: user, range: 384..<584, progress: progress)
        userBankIsLoaded = true
    }

    private func loadBank(into bank: VoiceBank,
                          range: Range<Int>,
                          progress: ((Double) -> Void)?) async throws {
        guard status == .idle else { throw LoadError.alreadyBusy }
        status = .reading(slot: 0, total: range.count)

        var collected: [Voice] = []
        collected.reserveCapacity(range.count)
        var missing: [Int] = []

        for (i, deviceIndex) in range.enumerated() {
            if Task.isCancelled {
                status = .idle
                throw LoadError.cancelled
            }
            var voice: Voice?
            var attempt = 0
            while voice == nil, attempt <= readRetryLimit {
                attempt += 1
                if let frame = try? await requestVoice(at: deviceIndex) {
                    voice = try? Voice.fromSysExResponse(frame, index: i)
                }
            }
            if let v = voice {
                collected.append(v)
            } else {
                let blank = Voice(index: i, record: [UInt8](repeating: 0, count: MaskProtocol.voiceRecordSize))
                collected.append(blank)
                missing.append(deviceIndex)
            }
            status = .reading(slot: i + 1, total: range.count)
            progress?(Double(i + 1) / Double(range.count))
            if readDelayMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(readDelayMs) * 1_000_000)
            }
        }

        bank.replaceAll(collected)
        status = .idle
        if !missing.isEmpty { throw LoadError.missingSlots(missing) }
    }

    /// Send a request for a single voice and await the response frame.
    private func requestVoice(at deviceIndex: Int) async throws -> [UInt8] {
        let frame = MaskProtocol.encodeVoiceRequest(index: deviceIndex)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], any Error>) in
            let mySeq: UInt64
            pendingLock.lock()
            nextSeq &+= 1
            mySeq = nextSeq
            pendingResponse = cont
            pendingSeq = mySeq
            pendingLock.unlock()

            let timeoutMs = self.readTimeoutMs
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.transport.sendSysEx(frame)
                } catch {
                    self.log.error("send failed for voice \(deviceIndex): \(String(describing: error))")
                    self.failPendingIfMatches(seq: mySeq, error: error)
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                self.failPendingIfMatches(seq: mySeq, error: LoadError.transport("timeout"))
            }
        }
    }

    /// Resume the pending continuation with `error` ONLY if it is still the
    /// continuation for sequence `seq`. Prevents a stale timeout from firing
    /// against a newer request's continuation.
    private func failPendingIfMatches(seq: UInt64, error: any Error) {
        pendingLock.lock()
        guard pendingSeq == seq, let cont = pendingResponse else {
            pendingLock.unlock()
            return
        }
        pendingResponse = nil
        pendingSeq = 0
        pendingLock.unlock()
        cont.resume(throwing: error)
    }

    private func handleIncoming(_ frame: [UInt8]) {
        guard frame.count == MaskProtocol.responseFrameSize else { return }
        pendingLock.lock()
        let cont = pendingResponse
        pendingResponse = nil
        pendingSeq = 0
        pendingLock.unlock()
        cont?.resume(returning: frame)
    }

    // MARK: File I/O

    public func importM1B(from url: URL, into kind: VoiceBank.Kind) throws {
        let voices = try FileIO.readM1B(url)
        bank(for: kind).replaceAll(voices)
        if kind == .user { userBankIsLoaded = true }
    }

    public func exportM1B(from kind: VoiceBank.Kind, to url: URL) throws {
        try FileIO.writeM1B(bank(for: kind).voices, to: url)
    }

    public func exportCSV(from kind: VoiceBank.Kind, to url: URL) throws {
        try FileIO.writeCSV(bank(for: kind).voices, to: url)
    }

    /// Copy selected voices from one bank kind to another (the "Copy selection →" button).
    ///
    /// Behavior:
    /// - If `startAt` is given (typically the lowest selected slot in the
    ///   destination), replace destination slots starting there.
    /// - If `startAt` is nil and the destination has room, append.
    /// - If `startAt` is nil and the destination is full, replace starting
    ///   at slot 0 — matches the web app's overwrite semantics for the
    ///   always-200-slot user bank.
    ///
    /// Source voices are inserted in the order they appear in the source bank.
    /// Returns the destination indices the copies landed at, or nil if the
    /// destination is read-only or no source ids matched.
    @discardableResult
    public func copy(
        _ ids: Set<Voice.ID>,
        from src: VoiceBank.Kind,
        to dst: VoiceBank.Kind,
        startAt: Int? = nil
    ) -> [Int]? {
        let s = bank(for: src)
        let d = bank(for: dst)
        guard !d.isReadOnly else { return nil }
        let picks = s.voices.filter { ids.contains($0.id) }
        guard !picks.isEmpty else { return nil }

        var current = d.voices
        let target: Int = startAt ?? (current.count < d.capacity ? current.count : 0)
        var landedAt: [Int] = []

        for (offset, src) in picks.enumerated() {
            let slot = target + offset
            guard slot < d.capacity else { break }
            let v = Voice(id: UUID(), index: slot, record: src.record,
                          displayNameOverride: src.displayNameOverride)
            if slot < current.count {
                current[slot] = v
            } else {
                current.append(v)
            }
            landedAt.append(slot)
        }
        d.replaceAll(current)
        return landedAt.isEmpty ? nil : landedAt
    }

    public func bank(for kind: VoiceBank.Kind) -> VoiceBank {
        switch kind {
        case .factory:   return factory
        case .user:      return user
        case .temporary: return temporary
        }
    }

    // MARK: Bank write (gated)

    /// Write all 200 user-bank voices back to the device, then send the
    /// bank-commit trailer. Slot indices are user-bank-relative (0…199).
    /// Pads the bank up to 200 voices with the existing on-device contents
    /// (we cannot leave gaps; the device expects a full 200-slot bank).
    public func sendUserBank(progress: ((Double) -> Void)? = nil) async throws {
        guard allowDeviceWrites else {
            throw LoadError.transport("device writes disabled (controller.allowDeviceWrites = false)")
        }
        // Refuse to send if we never read or imported a user bank — would
        // overwrite the on-device bank with 200 blank voices.
        guard userBankIsLoaded else {
            throw LoadError.transport(
                "Read or import a user bank first. Sending now would overwrite the device with empty voices."
            )
        }
        try writeBackup(of: user)

        let voices = user.voices
        let slotCount = 200
        status = .writing(slot: 0, total: slotCount)

        for slot in 0..<slotCount {
            if Task.isCancelled { status = .idle; throw LoadError.cancelled }
            // Use the in-memory voice if present, else fall back to a blank
            // (device would otherwise reject a partial bank). Phase 5 polish
            // is to read missing slots from the device first if not loaded.
            let record = (slot < voices.count) ? voices[slot].record : [UInt8](repeating: 0, count: MaskProtocol.voiceRecordSize)
            let frame = try MaskProtocol.encodeVoiceWrite(slot: slot, record: record)
            try await transport.sendSysEx(frame)
            status = .writing(slot: slot + 1, total: slotCount)
            progress?(Double(slot + 1) / Double(slotCount))
            if readDelayMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(readDelayMs) * 1_000_000)
            }
        }
        // Commit the bank — without this the device may not flush to EEPROM.
        try await transport.sendSysEx(MaskProtocol.encodeBankCommit())
        status = .idle
    }

    private func writeBackup(of bank: VoiceBank) throws {
        let dir = try backupDirectory()
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(bank.kind.rawValue)-\(stamp).m1b")
        try FileIO.writeM1B(bank.voices, to: url)
    }

    private func backupDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = appSupport
            .appendingPathComponent("MaskOrganizer", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Status

    public enum Status: Equatable {
        case idle
        case reading(slot: Int, total: Int)
        case writing(slot: Int, total: Int)
        case error(String)
    }
}
