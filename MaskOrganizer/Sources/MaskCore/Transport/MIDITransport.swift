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

    /// Send a 3-byte MIDI 1.0 Control Change (status `0xB0 | channel`).
    /// Used by the patch editor for live audition while editing.
    func sendChannelCC(channel: UInt8, cc: UInt8, value: UInt8) async throws

    /// Send a 2-byte MIDI 1.0 Program Change (status `0xC0 | channel`).
    /// Used by the patch editor on open to load the slot under edit so
    /// live CCs apply to the right voice.
    func sendProgramChange(channel: UInt8, program: UInt8) async throws
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
