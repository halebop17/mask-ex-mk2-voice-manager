import XCTest
@testable import MaskCore

final class VoiceBankTests: XCTestCase {

    private func sampleVoice(_ i: Int, name: String) -> Voice {
        var record = [UInt8](repeating: 0, count: 64)
        record[0] = UInt8(ascii: "x")  // arbitrary category byte
        for (k, b) in name.utf8.prefix(Voice.nameLength).enumerated() {
            record[Voice.nameOffset + k] = b
        }
        return Voice(index: i, record: record)
    }

    func testMoveReindexes() {
        let bank = VoiceBank(kind: .user, voices: [
            sampleVoice(0, name: "A"),
            sampleVoice(1, name: "B"),
            sampleVoice(2, name: "C"),
        ])
        bank.move(IndexSet(integer: 0), to: 3)
        XCTAssertEqual(bank.voices.map(\.displayName), ["B", "C", "A"])
        XCTAssertEqual(bank.voices.map(\.index), [0, 1, 2])
    }

    func testFactoryBankIsReadOnly() {
        let bank = VoiceBank(kind: .factory, voices: [sampleVoice(0, name: "X")])
        bank.move(IndexSet(integer: 0), to: 1)        // no-op
        XCTAssertEqual(bank.voices.first?.displayName, "X")

        XCTAssertThrowsError(try bank.remove(at: IndexSet(integer: 0))) { err in
            XCTAssertEqual(err as? VoiceBankError, .readOnlyBank)
        }
    }

    func testRenameSetsOverride() throws {
        let bank = VoiceBank(kind: .user, voices: [sampleVoice(0, name: "OLD")])
        try bank.rename(at: 0, to: "NEW")
        XCTAssertEqual(bank.voices[0].displayName, "NEW")
    }

    func testRemoveReindexes() throws {
        let bank = VoiceBank(kind: .user, voices: [
            sampleVoice(0, name: "A"),
            sampleVoice(1, name: "B"),
            sampleVoice(2, name: "C"),
        ])
        try bank.remove(at: IndexSet(integer: 1))
        XCTAssertEqual(bank.voices.map(\.displayName), ["A", "C"])
        XCTAssertEqual(bank.voices.map(\.index), [0, 1])
    }
}
