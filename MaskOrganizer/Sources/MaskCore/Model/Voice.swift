import Foundation

/// A single voice / preset.
///
/// Canonical form is the 64-byte raw record (matches `.m1b` layout).
/// Conversion to/from the 132-byte SysEx response frame is provided.
///
/// Layout of the 64-byte record (cross-checked against the web Voice
/// Organizer's display of the same bank):
///   byte  [0]    — category / tag byte (`x`, `y`, `z`, `{`, …). The web app
///                  shows this as a small badge but not as part of the name.
///   bytes [1…8]  — 8-char ASCII voice name (null- or space-padded)
///   bytes [9…63] — 55 bytes of voice parameters (raw, not nibble-encoded)
///
/// **Caveat:** factory voices captured via SysEx have `0x87` at byte [0] and
/// don't carry an ASCII name in bytes [1..8] (gibberish). For those,
/// `parsedName` returns nil and `displayName` falls back to a slot-based label.
public struct Voice: Equatable, Hashable, Codable, Identifiable {
    /// Stable identity within an in-memory bank.
    public let id: UUID
    /// Slot index on the device or in the file.
    public var index: Int
    /// 64 raw bytes — the canonical record form.
    public var record: [UInt8]
    /// User-set or imported display name (overrides `parsedName` if non-nil).
    public var displayNameOverride: String?

    public init(
        id: UUID = UUID(),
        index: Int,
        record: [UInt8],
        displayNameOverride: String? = nil
    ) {
        precondition(record.count == MaskProtocol.voiceRecordSize,
                     "voice record must be \(MaskProtocol.voiceRecordSize) bytes")
        self.id = id
        self.index = index
        self.record = record
        self.displayNameOverride = displayNameOverride
    }

    // MARK: Name and category

    /// Number of displayable characters in the embedded name field.
    public static let nameLength = 8
    /// Byte offset where the name starts within the 64-byte record.
    public static let nameOffset = 1

    /// Category byte (record[0]). For `.m1b`-loaded voices this is `x`/`y`/`z`/`{`
    /// or similar; for SysEx-loaded factory voices this is `0x87`.
    public var category: UInt8 { record[0] }

    /// Best-effort ASCII parse of bytes [1…8]. Returns nil if the slice
    /// contains any non-printable byte (factory SysEx voices fall here).
    public var parsedName: String? {
        let nameSlice = Array(record[Self.nameOffset..<(Self.nameOffset + Self.nameLength)])
        let trimmed = trimRight(nameSlice)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else { return nil }
        return String(bytes: trimmed, encoding: .ascii)
    }

    /// Name to show in the UI. Falls back to a slot-based label when the
    /// embedded name is unparseable.
    public var displayName: String {
        if let override = displayNameOverride, !override.isEmpty { return override }
        if let parsed = parsedName { return parsed }
        return String(format: "Voice %03d", index)
    }

    /// 55 voice-parameter bytes (the audio-shaping portion of the record).
    public var parameters: ArraySlice<UInt8> {
        record[(Self.nameOffset + Self.nameLength)..<MaskProtocol.voiceRecordSize]
    }

    // MARK: Construction from external formats

    /// Build a `Voice` from a 132-byte on-wire SysEx response frame.
    public static func fromSysExResponse(_ frame: [UInt8], index: Int) throws -> Voice {
        let nibbles = try MaskProtocol.decodeVoiceResponse(frame)
        let record = try MaskProtocol.nibblePack(nibbles)
        return Voice(index: index, record: record)
    }

    /// Build a `Voice` from a 64-byte `.m1b` record.
    public static func fromM1BRecord(_ bytes: [UInt8], index: Int) throws -> Voice {
        guard bytes.count == MaskProtocol.voiceRecordSize else {
            throw MaskProtocol.Error.wrongLength(bytes.count)
        }
        return Voice(index: index, record: bytes)
    }

    // MARK: Serialization

    /// 64-byte `.m1b` record (raw). If `displayNameOverride` is set, it
    /// overwrites bytes [1..8] with the override name (null-padded, 8 chars max).
    /// The category byte at [0] is preserved.
    public func m1bRecord() -> [UInt8] {
        var out = record
        if let name = displayNameOverride {
            let asciiBytes = Array(name.utf8.prefix(Self.nameLength))
            for i in 0..<Self.nameLength {
                out[Self.nameOffset + i] = i < asciiBytes.count ? asciiBytes[i] : 0x00
            }
        }
        return out
    }

    /// 132-byte SysEx response frame, useful for `.syx` export and round-trip
    /// testing. Uses opcode 0x02 framing — same shape as a device response.
    public func sysExResponseFrame() -> [UInt8] {
        let nibbles = MaskProtocol.nibbleExpand(m1bRecord())
        return [MaskProtocol.sysExStart]
            + MaskProtocol.manufacturerID
            + nibbles
            + [MaskProtocol.sysExEnd]
    }

    // MARK: Helpers

    private func trimRight(_ bytes: [UInt8]) -> [UInt8] {
        var end = bytes.count
        while end > 0 {
            let b = bytes[end - 1]
            if b == 0x00 || b == 0x20 { end -= 1 } else { break }
        }
        return Array(bytes.prefix(end))
    }
}
