import SwiftUI
import MaskCore

struct StatusPill: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(dotColor.opacity(0.3), lineWidth: 2).blur(radius: 1))
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(background)
        )
        .overlay(Capsule().stroke(border, lineWidth: 0.5))
    }

    private var label: String {
        switch state {
        case .disconnected:      return "Disconnected"
        case .searching:         return "Searching…"
        case .connected(let n):  return "Connected · \(n)"
        case .error(let msg):    return "Error: \(msg)"
        }
    }

    private var dotColor: Color {
        switch state {
        case .connected: return Theme.connectedGreen
        case .searching: return .orange
        case .error:     return .red
        case .disconnected: return Color(white: 0.78)
        }
    }
    private var background: Color {
        switch state {
        case .connected: return Theme.connectedGreen.opacity(0.10)
        case .error:     return Color.red.opacity(0.10)
        default:         return Color(white: 0.96)
        }
    }
    private var border: Color {
        switch state {
        case .connected: return Theme.connectedGreen.opacity(0.45)
        case .error:     return Color.red.opacity(0.45)
        default:         return Color.black.opacity(0.18)
        }
    }
    private var textColor: Color {
        switch state {
        case .connected: return Color(red: 0.05, green: 0.43, blue: 0.18)
        case .error:     return Color.red
        default:         return Color(white: 0.43)
        }
    }
}
