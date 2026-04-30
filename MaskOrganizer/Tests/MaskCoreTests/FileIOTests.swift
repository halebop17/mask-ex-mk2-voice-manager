import XCTest
@testable import MaskCore

final class FileIOTests: XCTestCase {

    func testParseM1BLoads271Voices() throws {
        let bank = try Fixtures.aviBank()
        let voices = try FileIO.parseM1B(bank)
        XCTAssertEqual(voices.count, 271)
        XCTAssertEqual(voices[0].displayName, "AF SIN I")
    }

    func testM1BUnalignedRejected() {
        let bytes = [UInt8](repeating: 0, count: 130) // not a multiple of 64
        XCTAssertThrowsError(try FileIO.parseM1B(bytes)) { err in
            XCTAssertEqual(err as? FileIO.Error, .unalignedM1B(130))
        }
    }

    func testM1BWriteReadRoundTrip() throws {
        let original = try FileIO.parseM1B(try Fixtures.aviBank())
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("roundtrip-\(UUID().uuidString).m1b")
        defer { _ = try? FileManager.default.removeItem(at: url) }

        try FileIO.writeM1B(original, to: url)
        let loaded = try FileIO.readM1B(url)

        XCTAssertEqual(loaded.count, original.count)
        for (a, b) in zip(loaded, original) {
            XCTAssertEqual(a.record, b.record)
        }

        // Bytes-on-disk identical to source bank.
        let onDisk = try Data(contentsOf: url)
        let source = try Fixtures.aviBank()
        XCTAssertEqual(Array(onDisk), source)
    }

    func testSyxRoundTrip() throws {
        let voices = try FileIO.parseM1B(try Fixtures.aviBank()).prefix(5)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("roundtrip-\(UUID().uuidString).syx")
        defer { _ = try? FileManager.default.removeItem(at: url) }

        try FileIO.writeSyx(Array(voices), to: url)
        let loaded = try FileIO.readSyx(url)
        XCTAssertEqual(loaded.count, 5)
        for (a, b) in zip(loaded, voices) {
            XCTAssertEqual(a.record, b.record)
        }
    }

    func testCSVHasOneHeaderAndOneRowPerVoice() throws {
        let voices = try FileIO.parseM1B(try Fixtures.aviBank()).prefix(3)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).csv")
        defer { _ = try? FileManager.default.removeItem(at: url) }
        try FileIO.writeCSV(Array(voices), to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 4) // header + 3 rows
        XCTAssertEqual(lines[0], "slot,name")
        XCTAssertTrue(lines[1].contains("AF SIN I"))
    }
}
