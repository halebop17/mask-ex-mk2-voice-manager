import SwiftUI
import AppKit
import MaskCore

@main
struct MaskOrganizerApp: App {
    @State private var controller: BankController = {
        // Real CoreMIDI transport in production. If init fails (unlikely outside
        // a sandbox without MIDI entitlements), fall back to a no-op transport
        // so the UI still renders for visual development.
        do {
            let midi = try MIDIManager()
            return BankController(transport: midi)
        } catch {
            return BankController(transport: NullTransport())
        }
    }()

    init() {
        // Without an .app bundle, SwiftPM-built executables register as
        // accessory-policy by default — window opens behind other apps and
        // the Dock shows nothing. Force a regular app policy and bring to
        // the front. Harmless when running from a real .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            // Force-show every window of this app — defensive belt-and-braces
            // for SwiftUI cases where the window exists but never gets
            // ordered to the front.
            for window in NSApplication.shared.windows {
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup("Mask EX Voice Manager") {
            ContentView(controller: controller)
                .preferredColorScheme(.light) // dark-mode polish deferred
                .onAppear {
                    // Last-resort window activation — runs *after* SwiftUI has
                    // built the window, so NSApplication.shared.windows is
                    // populated.
                    DispatchQueue.main.async {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        for window in NSApp.windows {
                            if !window.isVisible {
                                window.center()
                                window.makeKeyAndOrderFront(nil)
                            }
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {} // remove "New Window"
        }
    }
}

/// Fallback transport used only if CoreMIDI client creation fails. Exposes
/// no device, throws on send. Allows UI development without hardware.
final class NullTransport: MIDITransport, @unchecked Sendable {
    let connectionState: AsyncStream<ConnectionState>
    let incomingSysEx: AsyncStream<[UInt8]>
    private let s: AsyncStream<ConnectionState>.Continuation
    private let x: AsyncStream<[UInt8]>.Continuation
    var isConnected: Bool { false }

    init() {
        var sc: AsyncStream<ConnectionState>.Continuation!
        connectionState = AsyncStream { sc = $0 }
        s = sc
        var xc: AsyncStream<[UInt8]>.Continuation!
        incomingSysEx = AsyncStream { xc = $0 }
        x = xc
        s.yield(.disconnected)
    }
    func connect() async throws { throw MIDITransportError.deviceNotFound(name: "Mask1EX MK2") }
    func disconnect() {}
    func sendSysEx(_ frame: [UInt8]) async throws { throw MIDITransportError.notConnected }
    func sendChannelCC(channel: UInt8, cc: UInt8, value: UInt8) async throws { throw MIDITransportError.notConnected }
    func sendProgramChange(channel: UInt8, program: UInt8) async throws { throw MIDITransportError.notConnected }
}
