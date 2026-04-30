import XCTest
@testable import MaskCore

/// In-memory transport that records sends and replays canned responses.
/// One pending response is supported at a time (matches BankController's
/// single-in-flight request model during bulk reads).
final class FakeTransport: MIDITransport, @unchecked Sendable {
    let connectionState: AsyncStream<ConnectionState>
    let incomingSysEx: AsyncStream<[UInt8]>
    private let stateCont: AsyncStream<ConnectionState>.Continuation
    private let sysexCont: AsyncStream<[UInt8]>.Continuation

    var sentFrames: [[UInt8]] = []
    var responder: ([UInt8]) -> [UInt8]? = { _ in nil }
    private(set) var isConnected: Bool = false

    init() {
        var s: AsyncStream<ConnectionState>.Continuation!
        connectionState = AsyncStream { s = $0 }
        stateCont = s
        var x: AsyncStream<[UInt8]>.Continuation!
        incomingSysEx = AsyncStream { x = $0 }
        sysexCont = x
    }

    func connect() async throws {
        isConnected = true
        stateCont.yield(.connected(deviceName: "FakeDevice"))
    }

    func disconnect() {
        isConnected = false
        stateCont.yield(.disconnected)
    }

    func sendSysEx(_ frame: [UInt8]) async throws {
        sentFrames.append(frame)
        if let response = responder(frame) {
            // Yield asynchronously so the controller's `await` sees it after
            // it has registered its continuation.
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                self.sysexCont.yield(response)
            }
        }
    }
}

final class BankControllerTests: XCTestCase {

    func testFactoryReadCallsRequestForEachVoice() async throws {
        let fake = FakeTransport()
        // Build a simple responder: every request → an "all-zero" voice frame
        // that decodes to a 64-byte zero record. We use the captured first
        // factory response to keep things realistic.
        let canned = try Fixtures.responseFirst()
        fake.responder = { _ in canned }

        let controller = BankController(transport: fake)
        controller.readDelayMs = 0     // no inter-request delay in tests
        controller.readTimeoutMs = 200

        try await fake.connect()
        // Limit the test to a small range by reading a partial bank manually.
        // We invoke `loadFactoryBank` with progress to exercise the full path
        // but keep the test fast by not actually reading 377 voices —
        // the full read takes 377 × 1ms = 377ms which is fine.
        try await controller.loadFactoryBank(progress: nil)

        XCTAssertEqual(controller.temporary.voices.count, 377)
        XCTAssertEqual(fake.sentFrames.count, 377)
        // First sent frame is request for index 0.
        XCTAssertEqual(fake.sentFrames.first, [0xF0, 0x00, 0x00, 0x02, 0x00, 0x00, 0xF7])
    }

    func testTimeoutRetriesAndMarksMissing() async throws {
        let fake = FakeTransport()
        // Respond to all requests except slot 5 (device index 5) → triggers timeout.
        let canned = try Fixtures.responseFirst()
        fake.responder = { frame in
            // Decode the index from the request to skip a specific one.
            let idx = (try? MaskProtocol.decodeVoiceRequest(frame)) ?? -1
            return idx == 5 ? nil : canned
        }
        let controller = BankController(transport: fake)
        controller.readDelayMs = 0
        controller.readTimeoutMs = 30
        controller.readRetryLimit = 1
        try await fake.connect()

        // Run a small custom range by faking factory bank size. We instead
        // monkey-patch by reading factory and expecting it to throw missingSlots.
        do {
            try await controller.loadFactoryBank(progress: nil)
            XCTFail("expected missingSlots error")
        } catch let BankController.LoadError.missingSlots(slots) {
            XCTAssertEqual(slots, [5])
            // Bank still populated for the rest:
            XCTAssertEqual(controller.temporary.voices.count, 377)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
