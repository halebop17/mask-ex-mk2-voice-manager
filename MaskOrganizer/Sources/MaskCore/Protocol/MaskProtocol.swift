import Foundation

/// Stateless byte transformer for the Kodamo Mask1EX MK2 SysEx protocol.
///
/// On-wire format reverse-engineered from `factory-dump.mmon`:
///
///   Request  (HOST → DEVICE) :  F0 00 00 02 LSB MSB F7         ( 7 bytes)
///   Response (DEVICE → HOST) :  F0 00 00 [128 nibble bytes] F7 (132 bytes)
///
/// The 128 nibble bytes pack down to 64 raw bytes — the same layout used by
/// `.m1b` files. Voice index N is encoded across two 7-bit MIDI bytes:
///   LSB = N & 0x7F   ;   MSB = (N >> 7) & 0x7F
///
/// The "write voice" opcode is *assumed* to be 0x03 (symmetric to 0x02) but is
/// unconfirmed — see `encodeVoiceWrite`.
public enum MaskProtocol {

    public enum Opcode: UInt8 {
        case writeVoice   = 0x01  // confirmed via user-bank-write.mmon capture
        case requestVoice = 0x02
        case bankCommit   = 0x05  // sent after a bulk write to commit / end-of-bank
    }

    public enum Error: Swift.Error, Equatable {
        case badFraming             // missing F0/F7
        case wrongLength(Int)
        case badManufacturer        // expected 00 00 after F0
        case badPayload(String)
    }

    // MARK: Constants

    public static let manufacturerID: [UInt8] = [0x00, 0x00]
    public static let sysExStart: UInt8 = 0xF0
    public static let sysExEnd:   UInt8 = 0xF7

    /// Number of nibble bytes inside a voice response payload.
    public static let voicePayloadNibbleCount = 128
    /// Number of raw bytes per voice after nibble-packing (matches .m1b record size).
    public static let voiceRecordSize = 64

    /// Total size of a request frame on the wire (F0 + 4 + F7).
    public static let requestFrameSize = 7
    /// Total size of a voice response frame on the wire (F0 + 3 + 128 + F7).
    public static let responseFrameSize = 132

    // MARK: Requests

    /// Build the 7-byte SysEx that asks the device for voice `index`.
    public static func encodeVoiceRequest(index: Int) -> [UInt8] {
        precondition(index >= 0 && index < (1 << 14), "voice index out of 14-bit range")
        let lsb = UInt8(index & 0x7F)
        let msb = UInt8((index >> 7) & 0x7F)
        return [sysExStart] + manufacturerID + [Opcode.requestVoice.rawValue, lsb, msb, sysExEnd]
    }

    /// Inverse of `encodeVoiceRequest`. Returns the voice index, or throws.
    public static func decodeVoiceRequest(_ frame: [UInt8]) throws -> Int {
        guard frame.count == requestFrameSize else { throw Error.wrongLength(frame.count) }
        guard frame.first == sysExStart, frame.last == sysExEnd else { throw Error.badFraming }
        guard Array(frame[1..<3]) == manufacturerID else { throw Error.badManufacturer }
        guard frame[3] == Opcode.requestVoice.rawValue else {
            throw Error.badPayload("opcode \(String(format: "%02x", frame[3])) is not 0x02")
        }
        let lsb = Int(frame[4]); let msb = Int(frame[5])
        return (msb << 7) | lsb
    }

    // MARK: Responses

    /// Validate a 132-byte response frame and return the inner 128 nibble bytes.
    public static func decodeVoiceResponse(_ frame: [UInt8]) throws -> [UInt8] {
        guard frame.count == responseFrameSize else { throw Error.wrongLength(frame.count) }
        guard frame.first == sysExStart, frame.last == sysExEnd else { throw Error.badFraming }
        guard Array(frame[1..<3]) == manufacturerID else { throw Error.badManufacturer }
        let nibbles = Array(frame[3..<(3 + voicePayloadNibbleCount)])
        guard nibbles.allSatisfy({ $0 <= 0x0F }) else {
            throw Error.badPayload("non-nibble byte in voice payload")
        }
        return nibbles
    }

    // MARK: Writes (confirmed)

    /// Build a "write voice" SysEx. The destination index is **user-bank-relative**
    /// (0…199), not device-absolute — confirmed by the `user-bank-write.mmon`
    /// capture: the web app sent indices 0…199 with opcode 0x01 to write the
    /// 200 user-bank voices.
    ///
    /// On the wire: F0 + [00 00] + 0x01 + LSB + MSB + 128 nibble bytes + F7 = 135 bytes.
    public static func encodeVoiceWrite(slot: Int, record: [UInt8]) throws -> [UInt8] {
        guard record.count == voiceRecordSize else {
            throw Error.wrongLength(record.count)
        }
        precondition(slot >= 0 && slot < (1 << 14))
        let lsb = UInt8(slot & 0x7F)
        let msb = UInt8((slot >> 7) & 0x7F)
        return [sysExStart]
            + manufacturerID
            + [Opcode.writeVoice.rawValue, lsb, msb]
            + nibbleExpand(record)
            + [sysExEnd]
    }

    /// Build the bank-commit SysEx that closes a bulk write.
    ///
    /// On the wire: F0 00 00 05 7F 7F F7 (7 bytes). Captured at the tail of
    /// `user-bank-write.mmon`. Without it, the device may not commit writes
    /// to EEPROM. Fire-and-forget — no ACK observed.
    public static func encodeBankCommit() -> [UInt8] {
        return [sysExStart]
            + manufacturerID
            + [Opcode.bankCommit.rawValue, 0x7F, 0x7F, sysExEnd]
    }

    // MARK: Nibble pack/unpack

    /// 64 raw bytes → 128 4-bit nibble bytes (**low nibble first** — verified
    /// against the device by decoding factory voice 0 to `xDAWN…`, matching
    /// the web app's display).
    public static func nibbleExpand(_ bytes: [UInt8]) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            out.append(b & 0x0F)         // low nibble first
            out.append((b >> 4) & 0x0F)  // high nibble second
        }
        return out
    }

    /// 128 4-bit nibble bytes → 64 raw bytes. Throws if any input byte > 0x0F
    /// or the input length is odd.
    public static func nibblePack(_ nibbles: [UInt8]) throws -> [UInt8] {
        guard nibbles.count.isMultiple(of: 2) else {
            throw Error.wrongLength(nibbles.count)
        }
        guard nibbles.allSatisfy({ $0 <= 0x0F }) else {
            throw Error.badPayload("non-nibble byte in input")
        }
        var out = [UInt8]()
        out.reserveCapacity(nibbles.count / 2)
        for i in stride(from: 0, to: nibbles.count, by: 2) {
            // pair[0] is low nibble, pair[1] is high nibble
            out.append((nibbles[i + 1] << 4) | nibbles[i])
        }
        return out
    }
}
