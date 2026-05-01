import Foundation
import CoreMIDI
import os
import MaskCore

/// Production `MIDITransport` backed by CoreMIDI.
///
/// Responsibilities:
/// - Create a CoreMIDI client + input/output ports.
/// - Discover sources and destinations named `"Mask1EX MK2"`.
/// - Reassemble incoming SysEx across `MIDIPacket` boundaries (CoreMIDI may
///   split a long SysEx message). A complete frame (F0…F7) is published on
///   `incomingSysEx`.
/// - Send full SysEx frames via `MIDISendSysex` so the system handles
///   chunking on the way out.
/// - Re-discover the device when the MIDI configuration changes (hot-plug).
public final class MIDIManager: MIDITransport, @unchecked Sendable {

    public static let deviceName = "Mask1EX MK2"

    private let log = Logger(subsystem: "org.local.MaskOrganizer", category: "MIDI")

    // CoreMIDI handles
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var sourceEndpoint = MIDIEndpointRef()
    private var destinationEndpoint = MIDIEndpointRef()

    // SysEx reassembly buffer for inbound packets
    private var rxBuffer: [UInt8] = []
    private var rxLock = NSLock()

    // Async streams (state + incoming SysEx)
    public let connectionState: AsyncStream<ConnectionState>
    public let incomingSysEx: AsyncStream<[UInt8]>
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    private let sysexContinuation: AsyncStream<[UInt8]>.Continuation

    public private(set) var isConnected: Bool = false

    public init() throws {
        var stateCont: AsyncStream<ConnectionState>.Continuation!
        self.connectionState = AsyncStream { stateCont = $0 }
        self.stateContinuation = stateCont

        var sysexCont: AsyncStream<[UInt8]>.Continuation!
        self.incomingSysEx = AsyncStream { sysexCont = $0 }
        self.sysexContinuation = sysexCont

        try createClientAndPorts()
        stateContinuation.yield(.disconnected)
    }

    deinit {
        if client != 0 { MIDIClientDispose(client) }
        stateContinuation.finish()
        sysexContinuation.finish()
    }

    // MARK: Setup

    private func createClientAndPorts() throws {
        // Notify block fires on hot-plug etc. — re-resolve endpoints when it does.
        let notifyStatus = MIDIClientCreateWithBlock("MaskOrganizer" as CFString, &client) { [weak self] notification in
            self?.handleNotification(notification)
        }
        guard notifyStatus == noErr else { throw MIDITransportError.clientCreateFailed(notifyStatus) }

        let inStatus = MIDIInputPortCreateWithProtocol(
            client, "MaskOrganizer.Input" as CFString, ._1_0, &inputPort
        ) { [weak self] eventList, _ in
            self?.handleIncomingEventList(eventList)
        }
        guard inStatus == noErr else { throw MIDITransportError.portCreateFailed(inStatus) }

        let outStatus = MIDIOutputPortCreate(client, "MaskOrganizer.Output" as CFString, &outputPort)
        guard outStatus == noErr else { throw MIDITransportError.portCreateFailed(outStatus) }
    }

    // MARK: Connection

    public func connect() async throws {
        stateContinuation.yield(.searching)
        let (src, dst) = findEndpoints(named: Self.deviceName)
        guard src != 0, dst != 0 else {
            isConnected = false
            stateContinuation.yield(.disconnected)
            throw MIDITransportError.deviceNotFound(name: Self.deviceName)
        }
        // Disconnect any previous source first.
        if sourceEndpoint != 0 {
            MIDIPortDisconnectSource(inputPort, sourceEndpoint)
        }
        let status = MIDIPortConnectSource(inputPort, src, nil)
        guard status == noErr else {
            isConnected = false
            stateContinuation.yield(.error("MIDIPortConnectSource: \(status)"))
            throw MIDITransportError.portCreateFailed(status)
        }
        sourceEndpoint = src
        destinationEndpoint = dst
        isConnected = true
        stateContinuation.yield(.connected(deviceName: Self.deviceName))
        log.info("connected to \(Self.deviceName, privacy: .public)")
    }

    public func disconnect() {
        if sourceEndpoint != 0 {
            MIDIPortDisconnectSource(inputPort, sourceEndpoint)
        }
        sourceEndpoint = 0
        destinationEndpoint = 0
        isConnected = false
        stateContinuation.yield(.disconnected)
    }

    private func findEndpoints(named target: String) -> (source: MIDIEndpointRef, destination: MIDIEndpointRef) {
        var source: MIDIEndpointRef = 0
        var destination: MIDIEndpointRef = 0

        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)
            if displayName(of: endpoint).contains(target) {
                source = endpoint
                break
            }
        }
        let destCount = MIDIGetNumberOfDestinations()
        for i in 0..<destCount {
            let endpoint = MIDIGetDestination(i)
            if displayName(of: endpoint).contains(target) {
                destination = endpoint
                break
            }
        }
        return (source, destination)
    }

    private func displayName(of endpoint: MIDIEndpointRef) -> String {
        var prop: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &prop)
        if status == noErr, let cf = prop?.takeRetainedValue() {
            return cf as String
        }
        return ""
    }

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged:
            // Try to re-resolve endpoints. If we were connected and the device
            // disappeared, drop into disconnected state.
            let (src, dst) = findEndpoints(named: Self.deviceName)
            if src == 0 || dst == 0 {
                if isConnected { disconnect() }
            } else if isConnected, src != sourceEndpoint {
                // Device replaced. Reattach.
                MIDIPortDisconnectSource(inputPort, sourceEndpoint)
                _ = MIDIPortConnectSource(inputPort, src, nil)
                sourceEndpoint = src
                destinationEndpoint = dst
            }
        default:
            break
        }
    }

    // MARK: Inbound — SysEx reassembly

    private func handleIncomingEventList(_ eventList: UnsafePointer<MIDIEventList>) {
        let list = eventList.pointee
        var packetPtr = withUnsafePointer(to: list.packet) { $0 }
        for _ in 0..<list.numPackets {
            ingestEventPacket(packetPtr)
            packetPtr = UnsafePointer(MIDIEventPacketNext(UnsafeMutablePointer(mutating: packetPtr)))
        }
    }

    private func ingestEventPacket(_ packetPtr: UnsafePointer<MIDIEventPacket>) {
        let count = Int(packetPtr.pointee.wordCount)
        let words = withUnsafePointer(to: packetPtr.pointee.words) { ptr -> [UInt32] in
            ptr.withMemoryRebound(to: UInt32.self, capacity: count) {
                Array(UnsafeBufferPointer(start: $0, count: count))
            }
        }
        rxLock.lock()
        defer { rxLock.unlock() }
        parseSysExFromWords(words)
    }

    /// Iterates pairs of UMP words for MT=0x3 (SysEx-7).
    /// Each MT=0x3 UMP is 64 bits = 2 UInt32 words, layout:
    ///   word0 bits 31..28 = mt(=3); 27..24 = group; 23..20 = status; 19..16 = numBytes;
    ///         15..0 = first 2 data bytes (b0, b1)
    ///   word1 = 4 more data bytes (b2..b5)
    ///
    /// **CoreMIDI strips F0/F7 from the data bytes** of SysEx-7 UMPs — the
    /// framing is implicit in the status nibble (1=start, 3=end). We
    /// re-prepend F0 on start/complete and append F7 on end/complete so the
    /// rest of the codec can keep working with full on-wire frames.
    private func parseSysExFromWords(_ words: [UInt32]) {
        var i = 0
        while i < words.count {
            let w0 = words[i]
            let mt = (w0 >> 28) & 0xF
            guard mt == 0x3 else { i += 1; continue }
            guard i + 1 < words.count else { break }
            let w1 = words[i + 1]
            let status = (w0 >> 20) & 0x0F          // 0=complete, 1=start, 2=cont, 3=end
            let numBytes = Int((w0 >> 16) & 0x0F)   // 0..6
            var dataBytes: [UInt8] = []
            dataBytes.reserveCapacity(6)
            if numBytes >= 1 { dataBytes.append(UInt8((w0 >> 8) & 0xFF)) }
            if numBytes >= 2 { dataBytes.append(UInt8(w0 & 0xFF)) }
            if numBytes >= 3 { dataBytes.append(UInt8((w1 >> 24) & 0xFF)) }
            if numBytes >= 4 { dataBytes.append(UInt8((w1 >> 16) & 0xFF)) }
            if numBytes >= 5 { dataBytes.append(UInt8((w1 >> 8) & 0xFF)) }
            if numBytes >= 6 { dataBytes.append(UInt8(w1 & 0xFF)) }

            switch status {
            case 0x0: // complete (≤6 data bytes — whole message in one UMP)
                emitFrame(prefixF0: true, body: dataBytes, terminate: true)
            case 0x1: // start
                rxBuffer.removeAll(keepingCapacity: true)
                rxBuffer.append(0xF0)
                rxBuffer.append(contentsOf: dataBytes)
            case 0x2: // continue
                rxBuffer.append(contentsOf: dataBytes)
            case 0x3: // end
                rxBuffer.append(contentsOf: dataBytes)
                rxBuffer.append(0xF7)
                let frame = rxBuffer
                rxBuffer.removeAll(keepingCapacity: true)
                sysexContinuation.yield(frame)
            default:
                break
            }
            i += 2
        }
    }

    /// Emit a single-UMP "complete" SysEx with manual F0/F7 wrapping.
    private func emitFrame(prefixF0: Bool, body: [UInt8], terminate: Bool) {
        var frame: [UInt8] = []
        if prefixF0 { frame.append(0xF0) }
        frame.append(contentsOf: body)
        if terminate { frame.append(0xF7) }
        sysexContinuation.yield(frame)
    }

    // MARK: Outbound

    /// Submit a SysEx frame to CoreMIDI. Fire-and-forget — the system queues
    /// transmission asynchronously. Earlier versions awaited the completion
    /// callback, which serialized our outbound traffic against the device's
    /// roundtrip latency and added ~hundreds of ms per voice during bulk reads.
    /// CoreMIDI guarantees ordered delivery, so we just submit and trust it.
    public func sendSysEx(_ frame: [UInt8]) async throws {
        guard isConnected, destinationEndpoint != 0 else {
            throw MIDITransportError.notConnected
        }
        guard !frame.isEmpty, frame.first == 0xF0, frame.last == 0xF7 else {
            throw MIDIProtocolError.frameMustBeWrappedInSysEx
        }

        // Heap-allocated request + data buffer that the completion proc will
        // free after CoreMIDI is done with them.
        let request = UnsafeMutablePointer<MIDISysexSendRequest>.allocate(capacity: 1)
        let dataPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: frame.count)
        dataPtr.initialize(from: frame, count: frame.count)

        let box = SendContext(dataPtr: dataPtr, request: request)
        let opaque = Unmanaged.passRetained(box).toOpaque()

        request.initialize(to: MIDISysexSendRequest(
            destination: destinationEndpoint,
            data: UnsafePointer(dataPtr),
            bytesToSend: UInt32(frame.count),
            complete: false,
            reserved: (0, 0, 0),
            completionProc: { reqPtr in
                // Free the heap-backing for this request.
                let userInfo = reqPtr.pointee.completionRefCon!
                let box = Unmanaged<SendContext>.fromOpaque(userInfo).takeRetainedValue()
                box.dataPtr.deinitialize(count: Int(reqPtr.pointee.bytesToSend))
                box.dataPtr.deallocate()
                reqPtr.deinitialize(count: 1)
                reqPtr.deallocate()
            },
            completionRefCon: opaque
        ))

        let status = MIDISendSysex(request)
        if status != noErr {
            // Roll back on synchronous submission failure.
            _ = Unmanaged<SendContext>.fromOpaque(opaque).takeRetainedValue()
            dataPtr.deinitialize(count: frame.count)
            dataPtr.deallocate()
            request.deinitialize(count: 1)
            request.deallocate()
            throw MIDITransportError.sendFailed(status)
        }
    }

    // MARK: Channel-voice messages (CC, Program Change)

    public func sendChannelCC(channel: UInt8, cc: UInt8, value: UInt8) async throws {
        let status: UInt8 = 0xB0 | (channel & 0x0F)
        try sendShortMIDI(bytes: [status, cc & 0x7F, value & 0x7F])
    }

    public func sendProgramChange(channel: UInt8, program: UInt8) async throws {
        let status: UInt8 = 0xC0 | (channel & 0x0F)
        try sendShortMIDI(bytes: [status, program & 0x7F])
    }

    /// Send a 2- or 3-byte MIDI 1.0 channel-voice message via the new
    /// `MIDIEventList` API. Builds one MIDI 1.0 channel-voice UMP word
    /// (MT = 0x2) and ships it.
    private func sendShortMIDI(bytes: [UInt8]) throws {
        guard isConnected, destinationEndpoint != 0 else {
            throw MIDITransportError.notConnected
        }
        guard bytes.count == 2 || bytes.count == 3 else {
            throw MIDITransportError.packetTooLarge(bytes.count)
        }
        // Word layout (MIDI 1.0 channel voice UMP, MT=0x2):
        //   bits 31..28: MT     (= 0x2)
        //   bits 27..24: group  (= 0x0)
        //   bits 23..16: status byte
        //   bits 15..8 : data1
        //   bits 7..0  : data2 (0 if message is only 2 bytes)
        let status = UInt32(bytes[0])
        let data1  = UInt32(bytes[1])
        let data2: UInt32 = bytes.count == 3 ? UInt32(bytes[2]) : 0
        let word = (UInt32(0x2) << 28) | (status << 16) | (data1 << 8) | data2

        var eventList = MIDIEventList()
        var pkt = MIDIEventListInit(&eventList, ._1_0)
        // MIDIEventListAdd writes into eventList at `pkt` and returns the
        // next-write position. Critical: pkt must point into the SAME
        // event-list memory we then send, so do everything against
        // `&eventList` directly — never copy the list.
        pkt = withUnsafePointer(to: word) { wordPtr in
            MIDIEventListAdd(&eventList,
                             MemoryLayout<MIDIEventList>.size,
                             pkt,
                             0,           // timestamp = "now"
                             1,           // word count
                             wordPtr)
        }
        let result = MIDISendEventList(outputPort, destinationEndpoint, &eventList)
        if result != noErr {
            throw MIDITransportError.sendFailed(result)
        }
    }

    private final class SendContext {
        let dataPtr: UnsafeMutablePointer<UInt8>
        let request: UnsafeMutablePointer<MIDISysexSendRequest>
        init(dataPtr: UnsafeMutablePointer<UInt8>,
             request: UnsafeMutablePointer<MIDISysexSendRequest>) {
            self.dataPtr = dataPtr; self.request = request
        }
    }
}

public enum MIDIProtocolError: Swift.Error, Equatable {
    case frameMustBeWrappedInSysEx
}
