import SwiftUI
import MaskCore

struct StatusBar: View {
    let status: BankController.Status
    var onCancel: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            switch status {
            case .idle:
                Text("Ready").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            case .reading(let slot, let total):
                progress(label: "Reading voice \(slot) of \(total)", slot: slot, total: total)
            case .writing(let slot, let total):
                progress(label: "Writing voice \(slot) of \(total)", slot: slot, total: total)
            case .error(let msg):
                Text("Error: \(msg)").font(.system(size: 11)).foregroundStyle(.red)
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.background.secondary)
        .overlay(Divider(), alignment: .top)
    }

    @ViewBuilder
    private func progress(label: String, slot: Int, total: Int) -> some View {
        ProgressView()
            .controlSize(.small)
            .progressViewStyle(.circular)
        Text(label).font(.system(size: 11))
        ProgressView(value: Double(slot), total: Double(max(total, 1)))
            .progressViewStyle(.linear)
            .frame(width: 220)
        Text(String(format: "%d%%", Int((Double(slot) / Double(max(total, 1))) * 100)))
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
        Spacer()
        if let onCancel {
            Button("Cancel", action: onCancel)
                .controlSize(.small)
        }
    }
}
