import SwiftUI

struct CopyDivider: View {
    var onCopyRight: () -> Void
    var onCopyLeft: () -> Void
    var onCopyAllRight: () -> Void
    var onCopyAllLeft: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Button(action: onCopyRight) {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(.bordered)
            .help("Copy selection to user bank")
            Button(action: onCopyLeft) {
                Image(systemName: "arrow.left")
            }
            .buttonStyle(.bordered)
            .help("Copy selection to temporary")
            Spacer().frame(height: 8)
            Button(action: onCopyAllRight) {
                Image(systemName: "arrow.right.to.line")
            }
            .buttonStyle(.bordered)
            .help("Copy all temporary voices to user bank")
            Button(action: onCopyAllLeft) {
                Image(systemName: "arrow.left.to.line")
            }
            .buttonStyle(.bordered)
            .help("Copy all user-bank voices to temporary")
            Spacer()
        }
        .frame(width: 36)
        .background(Color(white: 0.95))
        .overlay(Divider(), alignment: .leading)
        .overlay(Divider(), alignment: .trailing)
    }
}
