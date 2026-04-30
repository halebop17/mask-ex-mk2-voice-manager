import Foundation
import XCTest

/// Loaders for files in `Tests/MaskCoreTests/Fixtures/`. SwiftPM packs them as
/// resources; we read via `Bundle.module`.
enum Fixtures {

    static func data(named name: String) throws -> [UInt8] {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw NSError(domain: "Fixtures", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
        }
        return Array(try Data(contentsOf: url))
    }

    static func responseFirst() throws -> [UInt8] { try data(named: "factory-response-000.bin") }
    static func responseLast()  throws -> [UInt8] { try data(named: "factory-response-last.bin") }
    static func requestFirst()  throws -> [UInt8] { try data(named: "factory-request-000.bin") }
    static func aviBank()       throws -> [UInt8] { try data(named: "avi-bank.m1b") }

    static func userWriteSlot0()   throws -> [UInt8] { try data(named: "user-write-slot-000.bin") }
    static func userWriteSlot5()   throws -> [UInt8] { try data(named: "user-write-slot-005.bin") }
    static func userWriteSlot199() throws -> [UInt8] { try data(named: "user-write-slot-199.bin") }
    static func userBankCommit()   throws -> [UInt8] { try data(named: "user-bank-commit.bin") }
    static func userReadRequest384() throws -> [UInt8] { try data(named: "user-read-request-384.bin") }
    static func userReadResponse0()  throws -> [UInt8] { try data(named: "user-read-response-000.bin") }
}
