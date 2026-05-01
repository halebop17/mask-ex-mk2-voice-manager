import XCTest
@testable import MaskCore

final class VoiceParametersTests: XCTestCase {

    // MARK: Table integrity

    func testAllParametersHaveUniqueStableIDs() {
        let ids = VoiceParameters.all.map(\.stableID)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate stableIDs in parameter table")
    }

    func testEveryGroupHasAtLeastOneParameter() {
        for group in ParameterGroup.allCases {
            XCTAssertFalse(
                VoiceParameters.parameters(in: group).isEmpty,
                "group \(group.displayName) has no parameters"
            )
        }
    }

    func testAllPrimaryCCsAreInValidRange() {
        for p in VoiceParameters.all {
            XCTAssertLessThanOrEqual(p.cc, 127, "\(p.stableID) primary CC out of range")
            for extra in p.extraCCs {
                XCTAssertLessThanOrEqual(extra, 127, "\(p.stableID) extra CC out of range")
            }
        }
    }

    func testParametersHaveExpectedCount() {
        // Sanity check: the manual lists ~58 logical voice parameters.
        // Allow some slack as we add/remove during Phase 7 polish.
        let count = VoiceParameters.all.count
        XCTAssertGreaterThanOrEqual(count, 50)
        XCTAssertLessThanOrEqual(count, 70)
    }

    // MARK: ValueFormat round-trip

    func testSignedFormatRoundTripsThroughCenter() {
        let format: ValueFormat = .signed(-64...63)
        XCTAssertEqual(format.userToStored(-64), 0)
        XCTAssertEqual(format.userToStored(0),   64)
        XCTAssertEqual(format.userToStored(63),  127)
        XCTAssertEqual(format.storedToUser(64),  0)
        XCTAssertEqual(format.storedToUser(0),   -64)
    }

    func testUnsignedFormatIsIdentity() {
        let format: ValueFormat = .unsigned(0...127)
        for v in stride(from: 0, through: 127, by: 13) {
            XCTAssertEqual(format.userToStored(v), v)
            XCTAssertEqual(format.storedToUser(v), v)
        }
    }

    // MARK: ccMessage routing

    func testSimpleCCMessage() {
        guard let cutoff = VoiceParameters.parameter(withID: "filter.cutoff") else {
            return XCTFail("filter.cutoff missing")
        }
        let (cc, value) = cutoff.ccMessage(for: 100)
        XCTAssertEqual(cc, 20)
        XCTAssertEqual(value, 100)
    }

    func testSignedCCMessageRoundTrip() {
        guard let pitch = VoiceParameters.parameter(withID: "general.transpose") else {
            return XCTFail("general.transpose missing")
        }
        // value 0 should send 64 (center of 0..127)
        let center = pitch.ccMessage(for: 0)
        XCTAssertEqual(center.cc, 9)
        XCTAssertEqual(center.value, 64)
        // value -64 should send 0
        let low = pitch.ccMessage(for: -64)
        XCTAssertEqual(low.value, 0)
        // value +63 should send 127
        let high = pitch.ccMessage(for: 63)
        XCTAssertEqual(high.value, 127)
    }

    func testMaskCCRoutesAcrossPages() {
        guard let mask = VoiceParameters.parameter(withID: "osc1.mask") else {
            return XCTFail("osc1.mask missing")
        }
        // Page 0: values 0..127 → CC 23
        XCTAssertEqual(mask.ccMessage(for: 0).cc, 23)
        XCTAssertEqual(mask.ccMessage(for: 127).cc, 23)
        XCTAssertEqual(mask.ccMessage(for: 127).value, 127)
        // Page 1: values 128..255 → CC 94
        XCTAssertEqual(mask.ccMessage(for: 128).cc, 94)
        XCTAssertEqual(mask.ccMessage(for: 128).value, 0)
        XCTAssertEqual(mask.ccMessage(for: 200).cc, 94)
        XCTAssertEqual(mask.ccMessage(for: 200).value, 72)
        // Page 2: values 256..383 → CC 46
        XCTAssertEqual(mask.ccMessage(for: 256).cc, 46)
        XCTAssertEqual(mask.ccMessage(for: 256).value, 0)
        // Page 3: values 384..511 → CC 48
        XCTAssertEqual(mask.ccMessage(for: 511).cc, 48)
        XCTAssertEqual(mask.ccMessage(for: 511).value, 127)
    }
}

// MARK: - BankController.setParameter integration

final class BankControllerEditingTests: XCTestCase {

    func testSetParameterSendsCC() async throws {
        let fake = FakeTransport()
        let ctrl = BankController(transport: fake)
        ctrl.midiChannel = 0

        guard let cutoff = VoiceParameters.parameter(withID: "filter.cutoff") else {
            return XCTFail("filter.cutoff missing")
        }
        await ctrl.setParameter(cutoff, value: 99)

        XCTAssertEqual(fake.sentCCs.count, 1)
        XCTAssertEqual(fake.sentCCs[0].channel, 0)
        XCTAssertEqual(fake.sentCCs[0].cc, 20)        // CC 20 = filter cutoff
        XCTAssertEqual(fake.sentCCs[0].value, 99)
    }

    func testSetParameterMaskRoutesCorrectPage() async throws {
        let fake = FakeTransport()
        let ctrl = BankController(transport: fake)

        guard let mask = VoiceParameters.parameter(withID: "osc1.mask") else {
            return XCTFail("osc1.mask missing")
        }
        await ctrl.setParameter(mask, value: 200)
        XCTAssertEqual(fake.sentCCs.count, 1)
        XCTAssertEqual(fake.sentCCs[0].cc, 94)        // page-1 CC for Osc1 mask
        XCTAssertEqual(fake.sentCCs[0].value, 72)     // 200 - 128
    }

    func testPrepareForEditingSendsProgramChange() async throws {
        let fake = FakeTransport()
        let ctrl = BankController(transport: fake)
        try await ctrl.prepareForEditing(slot: 17)
        XCTAssertEqual(fake.sentProgramChanges.count, 1)
        XCTAssertEqual(fake.sentProgramChanges[0].channel, 0)
        XCTAssertEqual(fake.sentProgramChanges[0].program, 17)
    }
}
