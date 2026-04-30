import Foundation

/// Abstraction over CoreMIDI used by `BankController`. Tests inject a fake
/// implementation that records `sendSysEx` and replays canned responses;
/// production uses `MIDIManager`.
public protocol MIDITransport: AnyObject, Sendable {
    var connectionState: AsyncStream<ConnectionState> { get }
    var incomingSysEx: AsyncStream<[UInt8]> { get }
    var isConnected: Bool { get }

    func connect() async throws
    func disconnect()
    func sendSysEx(_ frame: [UInt8]) async throws
}

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case searching
    case connected(deviceName: String)
    case error(String)
}

public enum MIDITransportError: Swift.Error, Equatable {
    case clientCreateFailed(OSStatus)
    case portCreateFailed(OSStatus)
    case deviceNotFound(name: String)
    case sendFailed(OSStatus)
    case notConnected
    case packetTooLarge(Int)
}
