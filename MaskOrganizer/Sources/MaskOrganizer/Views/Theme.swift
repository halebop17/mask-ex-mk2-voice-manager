import SwiftUI

/// Color and font tokens for the app. Mirrors the design mockup:
/// faint pane tints, dense rows, SF Mono for slot/voice names.
enum Theme {
    static let monoFont   = Font.system(size: 11.5, design: .monospaced)
    static let smallMono  = Font.system(size: 10.5, design: .monospaced)
    static let rowHeight: CGFloat = 22
    static let paneHeader: CGFloat = 38
    static let toolbar: CGFloat = 44

    enum Tint { case yellow, green }

    static func paneTint(_ t: Tint) -> Color {
        switch t {
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.25).opacity(0.10)
        case .green:  return Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.10)
        }
    }
    static func paneEdge(_ t: Tint) -> Color {
        switch t {
        case .yellow: return Color(red: 0.83, green: 0.66, blue: 0.14).opacity(0.35)
        case .green:  return Color(red: 0.16, green: 0.64, blue: 0.31).opacity(0.30)
        }
    }
    static func paneDot(_ t: Tint) -> Color {
        switch t {
        case .yellow: return Color(red: 0.91, green: 0.72, blue: 0.14)
        case .green:  return Color(red: 0.20, green: 0.66, blue: 0.32)
        }
    }
    static func tagBackground(_ t: Tint) -> Color {
        switch t {
        case .yellow: return Color(red: 0.91, green: 0.72, blue: 0.14).opacity(0.14)
        case .green:  return Color(red: 0.20, green: 0.66, blue: 0.32).opacity(0.14)
        }
    }

    static let modifiedDot = Color.orange
    static let connectedGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
}
