import XCTest
@testable import MaskCore

/// Verifies that our codec produces byte-identical output to what the
/// Kodamo web Voice Organizer sent on the wire (captured 2026-04-30).
final class CaptureConformanceTests: XCTestCase {

    func testBankCommitMatchesCapture() throws {
        let captured = try Fixtures.userBankCommit()
        XCTAssertEqual(captured, MaskProtocol.encodeBankCommit())
    }

    func testUserReadRequest384MatchesCapture() throws {
        let captured = try Fixtures.userReadRequest384()
        XCTAssertEqual(captured, MaskProtocol.encodeVoiceRequest(index: 384))
    }

    /// The captured write at slot 5 is exactly the voice that was at user-bank
    /// slot 0 before the user moved it. So: take read response 0, decode to
    /// Voice, encode as write to slot 5 — and we should get the captured frame.
    func testReadToWriteRoundTripMatchesCapture() throws {
        let readResponse = try Fixtures.userReadResponse0()
        let voice = try Voice.fromSysExResponse(readResponse, index: 0)

        let ourFrame = try MaskProtocol.encodeVoiceWrite(slot: 5, record: voice.record)
        let capturedWrite = try Fixtures.userWriteSlot5()
        XCTAssertEqual(ourFrame, capturedWrite,
                       "our encoded write frame for slot 5 must match the captured frame byte-for-byte")
    }

    func testCapturedWriteSlot199HasCorrectIndex() throws {
        let captured = try Fixtures.userWriteSlot199()
        // Layout: F0 00 00 01 LSB MSB ... F7
        XCTAssertEqual(captured[3], 0x01)        // write opcode
        // 199 = (1 << 7) | 71 → LSB=71 (0x47), MSB=1
        XCTAssertEqual(captured[4], 0x47)
        XCTAssertEqual(captured[5], 0x01)
    }
}
