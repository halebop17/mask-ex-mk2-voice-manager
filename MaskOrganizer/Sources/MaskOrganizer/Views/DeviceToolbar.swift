import SwiftUI
import MaskCore

struct DeviceToolbar: View {
    @Bindable var controller: BankController

    var body: some View {
        HStack(spacing: 10) {
            StatusPill(state: controller.connection)
            Button {
                Task {
                    if controller.connection == .disconnected {
                        try? await controller.connect()
                    } else {
                        controller.disconnect()
                    }
                }
            } label: {
                Label(connectLabel, systemImage: "powerplug")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
            Divider().frame(height: 22)
            Spacer()
            Text("v0.1 · macOS 14+")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.toolbar)
        .background(.background.secondary)
        .overlay(Divider(), alignment: .bottom)
    }

    private var connectLabel: String {
        switch controller.connection {
        case .disconnected, .error: return "Connect"
        default: return "Disconnect"
        }
    }
}
