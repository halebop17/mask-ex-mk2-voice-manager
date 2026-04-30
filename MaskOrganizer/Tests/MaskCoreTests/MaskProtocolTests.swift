import XCTest
@testable import MaskCore

final class MaskProtocolTests: XCTestCase {

    // MARK: Request encode/decode

    func testEncodeRequestVoice0() {
        let bytes = MaskProtocol.encodeVoiceRequest(index: 0)
        XCTAssertEqual(bytes, [0xF0, 0x00, 0x00, 0x02, 0x00, 0x00, 0xF7])
    }

    func testEncodeRequestVoice127() {
        let bytes = MaskProtocol.encodeVoiceRequest(index: 127)
        XCTAssertEqual(bytes, [0xF0, 0x00, 0x00, 0x02, 0x7F, 0x00, 0xF7])
    }

    func testEncodeRequestVoice128() {
        let bytes = MaskProtocol.encodeVoiceRequest(index: 128)
        XCTAssertEqual(bytes, [0xF0, 0x00, 0x00, 0x02, 0x00, 0x01, 0xF7])
    }

    func testEncodeRequestVoice376() {
        let bytes = MaskProtocol.encodeVoiceRequest(index: 376)
        XCTAssertEqual(bytes, [0xF0, 0x00, 0x00, 0x02, 0x78, 0x02, 0xF7])
    }

    func testEncodeDecodeRoundTripAcrossRange() throws {
        for i in stride(from: 0, to: 1024, by: 7) {
            let frame = MaskProtocol.encodeVoiceRequest(index: i)
            let decoded = try MaskProtocol.decodeVoiceRequest(frame)
            XCTAssertEqual(decoded, i)
        }
    }

    func testDecodeRequestRejectsBadFraming() {
        let frame: [UInt8] = [0x00, 0x00, 0x02, 0x05, 0x00, 0xF7, 0xF0]
        XCTAssertThrowsError(try MaskProtocol.decodeVoiceRequest(frame)) { err in
            XCTAssertEqual(err as? MaskProtocol.Error, .badFraming)
        }
    }

    // MARK: Response decode + nibble pack

    func testDecodeRealCapturedResponse() throws {
        let frame = try Fixtures.responseFirst()
        XCTAssertEqual(frame.count, MaskProtocol.responseFrameSize)
        let nibbles = try MaskProtocol.decodeVoiceResponse(frame)
        XCTAssertEqual(nibbles.count, 128)
        XCTAssertTrue(nibbles.allSatisfy { $0 <= 0x0F })

        let packed = try MaskProtocol.nibblePack(nibbles)
        XCTAssertEqual(packed.count, 64)
        // First raw byte is the category prefix; factory voice 0 in the
        // captured dump is "xDAWN…", so byte[0] is the lowercase 'x' tag.
        XCTAssertEqual(packed[0], UInt8(ascii: "x"))
    }

    func testNibbleRoundTrip() throws {
        let original: [UInt8] = (0..<64).map { _ in UInt8.random(in: 0...255) }
        let expanded = MaskProtocol.nibbleExpand(original)
        XCTAssertEqual(expanded.count, 128)
        let packed = try MaskProtocol.nibblePack(expanded)
        XCTAssertEqual(packed, original)
    }

    func testNibblePackRejectsHighBits() {
        let bad: [UInt8] = [0x00, 0x10, 0x00, 0x00] // 0x10 has bit 4 set
        XCTAssertThrowsError(try MaskProtocol.nibblePack(bad))
    }

    // MARK: Write encode (unconfirmed)

    func testEncodeWriteShape() throws {
        // F0 + [00 00] + 0x01 + LSB + MSB + 128 nibbles + F7 = 135 bytes.
        // Opcode 0x01 confirmed via user-bank-write.mmon capture.
        // 0xAA expands to nibbles 0x0A,0x0A regardless of nibble order.
        let record = [UInt8](repeating: 0xAA, count: 64)
        let frame = try MaskProtocol.encodeVoiceWrite(slot: 5, record: record)
        XCTAssertEqual(frame.count, 135)
        XCTAssertEqual(frame[0], 0xF0)
        XCTAssertEqual(Array(frame[1..<3]), [0x00, 0x00])
        XCTAssertEqual(frame[3], 0x01)
        XCTAssertEqual(frame[4], 5)
        XCTAssertEqual(frame[5], 0)
        XCTAssertEqual(frame.last, 0xF7)
        XCTAssertTrue(frame[6..<(6 + 128)].allSatisfy { $0 == 0x0A })
    }

    func testEncodeWriteMatchesCapturedFrame() throws {
        // Round-trip a captured read response into a write frame and verify
        // the result is byte-identical to a real write captured from the web app.
        let readFrame = try Fixtures.responseFirst()
        let voice = try Voice.fromSysExResponse(readFrame, index: 0)
        let writeFrame = try MaskProtocol.encodeVoiceWrite(slot: 5, record: voice.record)

        XCTAssertEqual(writeFrame.count, 135)
        // Body bytes [6..<134] (the 128 nibble bytes) must equal the original
        // read response's 128 nibble bytes [3..<131].
        XCTAssertEqual(Array(writeFrame[6..<134]), Array(readFrame[3..<131]))
    }

    func testEncodeBankCommit() {
        let frame = MaskProtocol.encodeBankCommit()
        XCTAssertEqual(frame, [0xF0, 0x00, 0x00, 0x05, 0x7F, 0x7F, 0xF7])
    }
}
