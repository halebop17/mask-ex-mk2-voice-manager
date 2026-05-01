import SwiftUI
import UniformTypeIdentifiers
import MaskCore

struct ContentView: View {
    @Bindable var controller: BankController

    @State private var temporarySelection: Set<Voice.ID> = []
    @State private var userSelection:      Set<Voice.ID> = []
    @State private var temporaryScrollTo:  Voice.ID? = nil
    @State private var userScrollTo:       Voice.ID? = nil
    @State private var focusedPaneID: VoiceBank.Kind? = .user
    /// Slot to drop the next copy into when the user hasn't explicitly
    /// selected a destination — advances after each copy so successive
    /// copies fill consecutive slots instead of overwriting each other.
    @State private var userPasteCursor: Int? = nil
    @State private var temporaryPasteCursor: Int? = nil
    /// IDs of the voices that landed in the last copy. Lets us tell whether
    /// the destination's current selection is a real user click or just
    /// auto-set by the previous copy.
    @State private var userLastLanded: Set<Voice.ID> = []
    @State private var temporaryLastLanded: Set<Voice.ID> = []
    @State private var loadTask: Task<Void, Never>?
    @State private var showImporter: Bool = false
    @State private var importTarget: VoiceBank.Kind = .temporary
    @State private var showExporter: Bool = false
    @State private var exportTarget: VoiceBank.Kind = .user
    @State private var exportSelectionOnly: Bool = false
    @State private var showCSVExporter: Bool = false
    @State private var csvTarget: VoiceBank.Kind = .user
    @State private var lastError: String? = nil
    @State private var showError: Bool = false
    @FocusState private var paneFocus: VoiceBank.Kind?
    /// Inspector visibility. Toggled by ⌘I, double-clicking a user-bank voice,
    /// or programmatically when a user-bank voice becomes singly selected.
    @State private var showInspector: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            DeviceToolbar(controller: controller)
            HStack(spacing: 0) {
                temporaryPane
                CopyDivider(
                    onCopyRight:    { copy(selection: temporarySelection, from: .temporary, to: .user) },
                    onCopyLeft:     { copy(selection: userSelection,      from: .user,      to: .temporary) },
                    onCopyAllRight: { copyAll(from: .temporary, to: .user) },
                    onCopyAllLeft:  { copyAll(from: .user,      to: .temporary) }
                )
                userPane
                if showInspector, let target = currentEditTarget {
                    VoiceDetailView(controller: controller, bank: target.bank, slot: target.slot)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            StatusBar(
                status: controller.status,
                onCancel: { loadTask?.cancel() }
            )
        }
        .animation(.easeInOut(duration: 0.18), value: showInspector)
        .frame(minWidth: showInspector ? 1480 : 1100, minHeight: 660)
        .onChange(of: userSelection)      { _, _ in autoCloseInspectorIfNeeded() }
        .onChange(of: temporarySelection) { _, _ in autoCloseInspectorIfNeeded() }
        // ⌘I toggle as an invisible hot button. Disabled when there's no
        // single user-bank selection AND the inspector isn't currently open
        // (so ⌘I from a closed state with no selection is a no-op).
        .background(
            Button("Toggle Inspector") { toggleInspector() }
                .keyboardShortcut("i", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.m1b, .syx]
        ) { result in
            // `importTarget` is set BEFORE we flip showImporter, so it's safe
            // to read here. Don't use a derived Binding for `isPresented` —
            // the system clears it before this completion runs.
            switch result {
            case .success(let url):
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    try controller.importM1B(from: url, into: importTarget)
                } catch {
                    lastError = "Couldn't load \(url.lastPathComponent): \(error)"
                    showError = true
                }
            case .failure(let err):
                lastError = err.localizedDescription
                showError = true
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: M1BDocument(voices: m1bVoicesForExport()),
            contentType: .m1b,
            defaultFilename: defaultFilename(for: exportTarget) + (exportSelectionOnly ? "-selection" : "")
        ) { result in
            if case .failure(let err) = result {
                lastError = err.localizedDescription
                showError = true
            }
        }
        .fileExporter(
            isPresented: $showCSVExporter,
            document: CSVDocument(voices: voices(for: csvTarget)),
            contentType: .commaSeparatedText,
            defaultFilename: defaultFilename(for: csvTarget)
        ) { result in
            if case .failure(let err) = result {
                lastError = err.localizedDescription
                showError = true
            }
        }
        .alert("Error", isPresented: $showError, presenting: lastError) { _ in
            Button("OK") {}
        } message: { msg in
            Text(msg)
        }
        // Keep mouse-driven focusedPaneID and FocusState in sync so the
        // focused pane is visually highlighted *and* receives key events.
        .onChange(of: paneFocus)     { _, new in focusedPaneID = new ?? focusedPaneID }
        .onChange(of: focusedPaneID) { _, new in paneFocus = new }
        .onAppear { paneFocus = focusedPaneID }
    }

    // MARK: Keyboard navigation

    /// Reorder: shift the currently-selected voice by `delta` (-1 = up, +1 = down).
    /// Only meaningful for editable banks; reorders within the focused pane.
    private func reorderSelection(in kind: VoiceBank.Kind, delta: Int) {
        let bank = controller.bank(for: kind)
        guard !bank.isReadOnly else { return }
        let currentSelection: Set<Voice.ID> = (kind == .user) ? userSelection : temporarySelection
        guard currentSelection.count == 1,
              let id = currentSelection.first,
              let i = bank.voices.firstIndex(where: { $0.id == id }) else { return }
        let newSlot = bank.shift(i, by: delta)
        guard newSlot != i else { return }
        // Selection follows the voice; keep paste cursor consistent.
        switch kind {
        case .user:
            userScrollTo = id
            userLastLanded = []
        case .temporary:
            temporaryScrollTo = id
            temporaryLastLanded = []
        case .factory:
            break
        }
    }

    private func moveSelection(in kind: VoiceBank.Kind, delta: Int) {
        let bank = controller.bank(for: kind)
        let voices = bank.voices
        guard !voices.isEmpty else { return }

        let currentSelection: Set<Voice.ID> = (kind == .user) ? userSelection : temporarySelection
        let currentIndex = voices.firstIndex(where: { currentSelection.contains($0.id) })
        let newIndex: Int
        if let i = currentIndex {
            newIndex = max(0, min(voices.count - 1, i + delta))
        } else {
            newIndex = delta > 0 ? 0 : voices.count - 1
        }
        let target = voices[newIndex]
        switch kind {
        case .user:
            userSelection = [target.id]
            userLastLanded = []         // user is now navigating manually
            userScrollTo = target.id
        case .temporary:
            temporarySelection = [target.id]
            temporaryLastLanded = []
            temporaryScrollTo = target.id
        case .factory:
            break
        }
    }

    // MARK: Action toolbars

    // MARK: Pane bodies (split out so SwiftUI's type-checker stays happy)

    @ViewBuilder
    private var temporaryPane: some View {
        BankListView(
            bank: controller.temporary,
            title: "Temporary",
            tint: .yellow,
            showModifiedColumn: false,
            selection: $temporarySelection,
            focusedPaneID: $focusedPaneID,
            scrollTo: $temporaryScrollTo,
            leftActions: AnyView(temporaryLeft),
            rightActions: AnyView(temporaryRight),
            onDoubleClick: { _ in openEditorForCurrentSelection() }
        )
        .focusable()
        .focused($paneFocus, equals: .temporary)
        .onKeyPress(keys: [.upArrow]) { handleArrow(in: .temporary, delta: -1, modifiers: $0.modifiers) }
        .onKeyPress(keys: [.downArrow]) { handleArrow(in: .temporary, delta: +1, modifiers: $0.modifiers) }
        .onKeyPress(.rightArrow) { paneFocus = .user; return .handled }
        .onKeyPress(.return)     { copy(selection: temporarySelection, from: .temporary, to: .user); return .handled }
    }

    @ViewBuilder
    private var userPane: some View {
        BankListView(
            bank: controller.user,
            title: "User Bank",
            tint: .green,
            showModifiedColumn: true,
            selection: $userSelection,
            focusedPaneID: $focusedPaneID,
            scrollTo: $userScrollTo,
            leftActions: AnyView(userLeft),
            rightActions: AnyView(userRight),
            onDoubleClick: { _ in openEditorForCurrentSelection() }
        )
        .focusable()
        .focused($paneFocus, equals: .user)
        .onKeyPress(keys: [.upArrow]) { handleArrow(in: .user, delta: -1, modifiers: $0.modifiers) }
        .onKeyPress(keys: [.downArrow]) { handleArrow(in: .user, delta: +1, modifiers: $0.modifiers) }
        .onKeyPress(.leftArrow)  { paneFocus = .temporary; return .handled }
        .onKeyPress(.return)     { copy(selection: userSelection, from: .user, to: .temporary); return .handled }
    }

    /// Up/Down arrow handler. Plain → move selection; ⌥ → reorder within pane.
    private func handleArrow(in kind: VoiceBank.Kind, delta: Int, modifiers: EventModifiers) -> KeyPress.Result {
        if modifiers.contains(.option) {
            reorderSelection(in: kind, delta: delta)
        } else {
            moveSelection(in: kind, delta: delta)
        }
        return .handled
    }

    // MARK: Inspector

    /// Bank + slot of the voice currently picked for editing — either the
    /// single selection in the user bank or the single selection in the
    /// temporary pane. Picks the focused pane when both have one selected.
    private var currentEditTarget: (bank: VoiceBank, slot: Int)? {
        let userSlot = singleSelectedSlot(in: userSelection, bank: controller.user)
        let tempSlot = singleSelectedSlot(in: temporarySelection, bank: controller.temporary)
        switch (userSlot, tempSlot) {
        case (let u?, let t?):
            // Both panes have a single selection — pick the focused one.
            return focusedPaneID == .temporary ? (controller.temporary, t) : (controller.user, u)
        case (let u?, nil):
            return (controller.user, u)
        case (nil, let t?):
            return (controller.temporary, t)
        default:
            return nil
        }
    }

    private func singleSelectedSlot(in selection: Set<Voice.ID>, bank: VoiceBank) -> Int? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return bank.voices.firstIndex(where: { $0.id == id })
    }

    /// Open the inspector for whichever pane has a single voice selected.
    ///
    /// We deliberately do **not** send Program Change here. The Mask1EX MK2
    /// needs a Bank Select (CC 32, "Banks 1–4 contain user voices") before
    /// PC, and the per-bank slot count isn't yet confirmed. Until bank-aware
    /// PC is wired up, the editor controls whatever voice is currently
    /// active on the synth — pick that voice on the front panel first.
    private func openEditorForCurrentSelection() {
        guard currentEditTarget != nil else { return }
        showInspector = true
    }

    private func autoCloseInspectorIfNeeded() {
        if currentEditTarget == nil { showInspector = false }
    }

    /// ⌘I toggle. Closes if open; opens (and prepares the device) if a single
    /// user voice is selected.
    private func toggleInspector() {
        if showInspector {
            showInspector = false
        } else {
            openEditorForCurrentSelection()
        }
    }

    private func openImporter(target: VoiceBank.Kind) {
        importTarget = target
        showImporter = true
    }
    private func openExporter(target: VoiceBank.Kind, selectionOnly: Bool = false) {
        exportTarget = target
        exportSelectionOnly = selectionOnly
        showExporter = true
    }

    /// Voices to export as `.m1b` — full bank, or only the currently-selected
    /// voices if `exportSelectionOnly` is set.
    private func m1bVoicesForExport() -> [Voice] {
        let bank = controller.bank(for: exportTarget)
        guard exportSelectionOnly else { return bank.voices }
        let ids: Set<Voice.ID> = (exportTarget == .user) ? userSelection : temporarySelection
        return bank.voices.filter { ids.contains($0.id) }
    }
    private func openCSVExporter(target: VoiceBank.Kind) {
        csvTarget = target
        showCSVExporter = true
    }

    private var temporaryLeft: some View {
        HStack(spacing: 5) {
            Button {
                resetCursors(for: .temporary)
                loadTask = Task { await runLoad { try await controller.loadFactoryBank() } }
            } label: {
                Label("Load Factory Bank", systemImage: "arrow.down.circle")
            }
            .controlSize(.small)
            .disabled(!isConnected)
            Button {
                resetCursors(for: .temporary)
                openImporter(target: .temporary)
            } label: {
                Label("From file…", systemImage: "doc")
            }
            .controlSize(.small)
        }
    }

    private var temporaryRight: some View {
        Button {
            openCSVExporter(target: .temporary)
        } label: {
            Label("CSV", systemImage: "tablecells")
        }
        .controlSize(.small)
    }

    private var userLeft: some View {
        HStack(spacing: 5) {
            Button {
                resetCursors(for: .user)
                loadTask = Task { await runLoad { try await controller.loadUserBank() } }
            } label: {
                Label("From device", systemImage: "arrow.down.circle")
            }
            .controlSize(.small)
            .disabled(!isConnected)
            Button {
                resetCursors(for: .user)
                openImporter(target: .user)
            } label: {
                Label("From file…", systemImage: "doc")
            }
            .controlSize(.small)
            Button {
                openExporter(target: .user)
            } label: {
                Label("Save bank…", systemImage: "arrow.up.circle")
            }
            .controlSize(.small)
            Button {
                openExporter(target: .user, selectionOnly: true)
            } label: {
                Label("Save selection…", systemImage: "square.and.arrow.up")
            }
            .controlSize(.small)
            .disabled(userSelection.isEmpty)
        }
    }

    /// True iff the transport reports an active device connection. Used to
    /// disable load/send buttons that have no chance of succeeding.
    private var isConnected: Bool {
        if case .connected = controller.connection { return true }
        return false
    }

    /// Run an async device call and surface any thrown error in the alert,
    /// including the partial-bank-loaded `missingSlots` case.
    private func runLoad(_ op: @escaping () async throws -> Void) async {
        do {
            try await op()
        } catch BankController.LoadError.missingSlots(let slots) {
            lastError = "\(slots.count) voice slots didn't respond. The device may be busy or disconnected."
            showError = true
        } catch {
            lastError = "\(error)"
            showError = true
        }
    }

    private func resetCursors(for kind: VoiceBank.Kind) {
        switch kind {
        case .user:
            userPasteCursor = nil
            userLastLanded = []
            userSelection = []
        case .temporary:
            temporaryPasteCursor = nil
            temporaryLastLanded = []
            temporarySelection = []
        case .factory:
            break
        }
    }

    private var userRight: some View {
        HStack(spacing: 5) {
            Button {
                openCSVExporter(target: .user)
            } label: {
                Label("CSV", systemImage: "tablecells")
            }
            .controlSize(.small)
            Divider().frame(height: 18)
            Button {
                Task { await runLoad { try await controller.sendUserBank() } }
            } label: {
                Label("Send to MASK1", systemImage: "arrow.right.circle.fill")
            }
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .buttonStyle(.borderedProminent)
            .disabled(!controller.allowDeviceWrites || !isConnected || !controller.userBankIsLoaded)
            .help(controller.userBankIsLoaded
                  ? "Write the user bank back to the device"
                  : "Read or import a user bank first")
        }
    }

    // MARK: Actions

    /// Copy every voice from src into dst, overwriting from slot 0.
    private func copyAll(from src: VoiceBank.Kind, to dst: VoiceBank.Kind) {
        let allIDs = Set(controller.bank(for: src).voices.map(\.id))
        // Reset cursor so the copy starts at slot 0.
        switch dst {
        case .user:      userPasteCursor = nil; userLastLanded = []; userSelection = []
        case .temporary: temporaryPasteCursor = nil; temporaryLastLanded = []; temporarySelection = []
        case .factory:   return
        }
        copy(selection: allIDs, from: src, to: dst)
    }

    private func copy(selection: Set<Voice.ID>, from src: VoiceBank.Kind, to dst: VoiceBank.Kind) {
        guard !selection.isEmpty else {
            lastError = "Select one or more voices in the \(src.rawValue) pane first."
            showError = true
            return
        }
        // Decide where to drop the copies:
        //  1. If the user *explicitly* selected a destination slot (selection
        //     differs from what we auto-set after the previous copy), use the
        //     lowest selected slot.
        //  2. Otherwise advance from the previous paste cursor.
        //  3. Falling back, the controller appends or starts at slot 0.
        let dstBank = controller.bank(for: dst)
        let dstSelectionIDs: Set<Voice.ID> = (dst == .user) ? userSelection : temporarySelection
        let lastLandedIDs:   Set<Voice.ID> = (dst == .user) ? userLastLanded : temporaryLastLanded
        let pasteCursor:     Int?         = (dst == .user) ? userPasteCursor : temporaryPasteCursor

        let userExplicitlySelected = !dstSelectionIDs.isEmpty && dstSelectionIDs != lastLandedIDs
        let startAt: Int?
        if userExplicitlySelected {
            let dstSelectedIndices = dstBank.voices.indices.filter { dstSelectionIDs.contains(dstBank.voices[$0].id) }
            startAt = dstSelectedIndices.min()
        } else {
            startAt = pasteCursor
        }

        guard let landed = controller.copy(selection, from: src, to: dst, startAt: startAt) else {
            lastError = "Couldn't copy: destination is read-only."
            showError = true
            return
        }
        let updatedDst = controller.bank(for: dst)
        let newIDs = Set(landed.compactMap { i -> Voice.ID? in
            guard i < updatedDst.voices.count else { return nil }
            return updatedDst.voices[i].id
        })
        let nextCursor: Int? = (landed.last.map { $0 + 1 }).flatMap { $0 < dstBank.capacity ? $0 : nil }

        // Update destination state (selection / scroll / paste cursor) but
        // do NOT steal focus from the source pane — the user wants to keep
        // navigating where they were.
        switch dst {
        case .user:
            userSelection = newIDs
            userLastLanded = newIDs
            userPasteCursor = nextCursor
            userScrollTo = newIDs.first
        case .temporary:
            temporarySelection = newIDs
            temporaryLastLanded = newIDs
            temporaryPasteCursor = nextCursor
            temporaryScrollTo = newIDs.first
        case .factory:
            break
        }
    }

    private func voices(for kind: VoiceBank.Kind) -> [Voice] {
        controller.bank(for: kind).voices
    }

    private func defaultFilename(for kind: VoiceBank.Kind) -> String {
        switch kind {
        case .factory:   return "factory-bank"
        case .user:      return "user-bank"
        case .temporary: return "temporary-bank"
        }
    }
}

// MARK: - File types & document

extension UTType {
    static let m1b = UTType(filenameExtension: "m1b") ?? UTType.data
    static let syx = UTType(filenameExtension: "syx") ?? UTType.data
}

/// A trivial FileDocument that exports the in-memory voice list as `.m1b`.
struct M1BDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.m1b]
    static let writableContentTypes: [UTType] = [.m1b]

    var voices: [Voice]

    init(voices: [Voice]) { self.voices = voices }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.voices = try FileIO.parseM1B(Array(data))
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var blob = Data()
        for v in voices { blob.append(contentsOf: v.m1bRecord()) }
        return FileWrapper(regularFileWithContents: blob)
    }
}

/// CSV export — slot number and display name, one row per voice.
struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    static let writableContentTypes: [UTType] = [.commaSeparatedText]

    var voices: [Voice]

    init(voices: [Voice]) { self.voices = voices }

    init(configuration: ReadConfiguration) throws {
        // Read-back not supported for CSV; this exporter is write-only.
        self.voices = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var lines = ["slot,name"]
        for v in voices {
            let escaped = v.displayName.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append(String(format: "%03d,\"%@\"", v.index + 1, escaped))
        }
        let text = lines.joined(separator: "\n") + "\n"
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
