import SwiftUI
import MaskCore

struct BankListView: View {
    @Bindable var bank: VoiceBank
    let title: String
    let tint: Theme.Tint
    let showModifiedColumn: Bool
    @Binding var selection: Set<Voice.ID>
    @Binding var focusedPaneID: VoiceBank.Kind?
    /// When set to a Voice.ID, the list scrolls that row into view and clears
    /// itself. Used by the parent after a copy operation.
    @Binding var scrollTo: Voice.ID?

    /// Per-pane action toolbars (factory differs from user). Provided by the
    /// parent so this view stays bank-agnostic.
    let leftActions: AnyView
    let rightActions: AnyView

    @State private var search: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            actionBar
            searchBar
            columnHeaders
            list
        }
        .background(Theme.paneTint(tint))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.paneEdge(tint)).frame(height: 2)
        }
        .onTapGesture { focusedPaneID = bank.kind }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.paneDot(tint))
                .frame(width: 7, height: 7)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(0.1), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(countLabel).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.paneHeader)
        .overlay(Divider(), alignment: .bottom)
    }

    private var actionBar: some View {
        HStack(spacing: 5) {
            leftActions
            Spacer()
            rightActions
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Color(white: 0.98))
        .overlay(Divider(), alignment: .bottom)
    }

    private var searchBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
            TextField("Search \(title.lowercased())", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(.background)
        .overlay(Divider(), alignment: .bottom)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 36, alignment: .leading)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Tag").frame(width: 36, alignment: .trailing)
            if showModifiedColumn { Spacer().frame(width: 14) }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background(Color(white: 0.985))
        .overlay(Divider(), alignment: .bottom)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredVoices) { voice in
                        let realIndex = bank.voices.firstIndex(where: { $0.id == voice.id }) ?? voice.index
                        VoiceRow(
                            voice: voice,
                            isSelected: selection.contains(voice.id),
                            isFocused: focusedPaneID == bank.kind,
                            isAlt: realIndex.isMultiple(of: 2) == false,
                            isModified: false,
                            showModifiedColumn: showModifiedColumn,
                            tagBackground: Theme.tagBackground(tint)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(voice.id, additive: NSEvent.modifierFlags.contains(.command))
                            focusedPaneID = bank.kind
                        }
                        .id(voice.id)
                    }
                }
            }
            .onChange(of: scrollTo) { _, newValue in
                if let id = newValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    scrollTo = nil
                }
            }
        }
    }

    // MARK: Helpers

    private var filteredVoices: [Voice] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return bank.voices }
        return bank.voices.filter { $0.displayName.lowercased().contains(q) }
    }

    private var countLabel: String {
        let n = bank.voices.count
        return "\(n) of \(bank.capacity) voices"
    }

    private func toggleSelection(_ id: Voice.ID, additive: Bool) {
        if additive {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }
}
