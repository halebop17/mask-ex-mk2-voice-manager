import XCTest
@testable import MaskCore

final class VoiceTests: XCTestCase {

    // MARK: SysEx → Voice

    func testFromSysExResponseDecodesFactoryVoice() throws {
        // First captured factory voice decodes to category 'x' + name "DAWN".
        // Confirms low-nibble-first packing matches the device.
        let frame = try Fixtures.responseFirst()
        let voice = try Voice.fromSysExResponse(frame, index: 0)
        XCTAssertEqual(voice.record.count, 64)
        XCTAssertEqual(voice.category, UInt8(ascii: "x"))
        XCTAssertEqual(voice.parsedName, "DAWN")
        XCTAssertEqual(voice.displayName, "DAWN")
    }

    // MARK: .m1b → Voice

    func testFromM1BRecordExtractsName() throws {
        let bank = try Fixtures.aviBank()
        XCTAssertEqual(bank.count % 64, 0)
        let firstRecord = Array(bank[0..<64])
        let voice = try Voice.fromM1BRecord(firstRecord, index: 0)
        // First record: byte[0] = 'x' (category), bytes[1..8] = "AF SIN I"
        XCTAssertEqual(voice.category, UInt8(ascii: "x"))
        XCTAssertEqual(voice.parsedName, "AF SIN I")
        XCTAssertEqual(voice.displayName, "AF SIN I")
    }

    func testCategoryByteIsPreserved() throws {
        // Record 2 in Avi's bank has category '{' (0x7B) and name "AFWTBLY".
        let bank = try Fixtures.aviBank()
        let rec2 = Array(bank[(2 * 64)..<(3 * 64)])
        let voice = try Voice.fromM1BRecord(rec2, index: 2)
        XCTAssertEqual(voice.category, UInt8(ascii: "{"))
        XCTAssertEqual(voice.parsedName, "AFWTBLY")
    }

    func testM1BRoundTripIsByteIdentical() throws {
        let bank = try Fixtures.aviBank()
        for i in 0..<(bank.count / 64) {
            let record = Array(bank[(i * 64)..<((i + 1) * 64)])
            let voice = try Voice.fromM1BRecord(record, index: i)
            XCTAssertEqual(voice.m1bRecord(), record, "round-trip differs at voice \(i)")
        }
    }

    // MARK: SysEx round-trip

    func testSysExResponseRoundTrip() throws {
        let frame = try Fixtures.responseFirst()
        let voice = try Voice.fromSysExResponse(frame, index: 0)
        let rebuilt = voice.sysExResponseFrame()
        XCTAssertEqual(rebuilt, frame, "SysEx response frame did not round-trip")
    }

    // MARK: Rename

    func testRenameOverridesNameField() throws {
        let bank = try Fixtures.aviBank()
        let record = Array(bank[0..<64])
        var voice = try Voice.fromM1BRecord(record, index: 0)
        voice.displayNameOverride = "MYNAME01"
        let exported = voice.m1bRecord()
        // Byte 0 (category) preserved.
        XCTAssertEqual(exported[0], record[0])
        // Bytes [1..8] are the renamed name.
        XCTAssertEqual(Array(exported[1..<9]), Array("MYNAME01".utf8))
        // Parameter bytes (9..63) unchanged.
        XCTAssertEqual(Array(exported[9..<64]), Array(record[9..<64]))
    }

    func testLongNameTruncatesToEightChars() throws {
        let bank = try Fixtures.aviBank()
        let record = Array(bank[0..<64])
        var voice = try Voice.fromM1BRecord(record, index: 0)
        voice.displayNameOverride = "thisistoolong"
        let exported = voice.m1bRecord()
        XCTAssertEqual(exported[0], record[0])  // category preserved
        XCTAssertEqual(Array(exported[1..<9]), Array("thisisto".utf8))
    }
}
