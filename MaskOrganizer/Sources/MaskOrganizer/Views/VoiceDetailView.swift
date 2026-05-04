import SwiftUI
import MaskCore

/// Right-hand inspector pane: edit one voice's parameters live.
///
/// Each control sends a MIDI CC to the device immediately on change so the
/// user hears the edit while playing notes. Save (writing the edit back to
/// the slot via SysEx) is gated until Phase 7.1's byte-offset map is done.
struct VoiceDetailView: View {
    @Bindable var controller: BankController
    let bank: VoiceBank
    /// The voice slot under edit (index in `bank.voices`).
    let slot: Int

    /// Local UI state: each parameter's current edited value, keyed by
    /// `VoiceParameter.stableID`. Lives in the view because we don't yet
    /// have byte offsets to persist into `voice.record`.
    @State private var values: [String: Int] = [:]
    /// Which parameters the user has actually moved during this editor session.
    /// Untouched sliders are rendered dimmed with no numeric readout — we
    /// don't know the device's stored value (Phase 7.1 byte map will fix that).
    @State private var touched: Set<String> = []
    @State private var expandedGroups: Set<ParameterGroup> = [.osc1, .filter]
    @State private var probeExpanded: Bool = false
    @State private var probeBaseline: [UInt8]? = nil   // captured from voice.record
    @State private var probeCurrent:  [UInt8]? = nil   // re-read from device
    @State private var probeReading:  Bool = false
    @State private var probeError:    String? = nil
    @State private var probeByteIndex: Int = 9
    @State private var probeWriting:   Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ParameterGroup.allCases, id: \.self) { group in
                        section(for: group)
                    }
                    probeSection
                }
                .padding(.vertical, 6)
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .background(.background)
        .overlay(Divider(), alignment: .leading)
        .onAppear {
            // Position sliders at the visual midpoint so they have a starting
            // location, but mark them all as "untouched" so the UI doesn't
            // claim those are the voice's actual values. Once Phase 7.1's
            // byte-offset map exists we'll read real values from voice.record.
            for p in VoiceParameters.all where values[p.stableID] == nil {
                values[p.stableID] = (p.range.lowerBound + p.range.upperBound) / 2
            }
            touched.removeAll()
        }
        .onChange(of: slot) { _, _ in
            // Switching to a different voice clears the touched set so we
            // don't carry the previous voice's edits visually.
            touched.removeAll()
        }
    }

    // MARK: Header

    private var header: some View {
        let voice = currentVoice
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(String(format: "%@%03d", slotPrefix, slot + 1))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(voice?.displayName ?? "—")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("Editor")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let cat = voice?.category, cat >= 0x20, cat <= 0x7E {
                    Text(String(UnicodeScalar(cat)))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            Text("Edits the voice currently active on the synth. Select it on the front panel first.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Section

    @ViewBuilder
    private func section(for group: ParameterGroup) -> some View {
        let params = VoiceParameters.parameters(in: group)
        if !params.isEmpty {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedGroups.contains(group) },
                    set: { isOpen in
                        if isOpen { expandedGroups.insert(group) } else { expandedGroups.remove(group) }
                    }
                )
            ) {
                VStack(spacing: 4) {
                    ForEach(params) { p in
                        parameterRow(p)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 6)
            } label: {
                Text(group.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.vertical, 4)
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: Parameter row

    @ViewBuilder
    private func parameterRow(_ p: VoiceParameter) -> some View {
        let isTouched = touched.contains(p.stableID)
        HStack(spacing: 8) {
            Text(p.displayName)
                .font(.system(size: 11.5))
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(isTouched ? .primary : .secondary)

            switch p.format {
            case .menu(let options):
                Picker("", selection: bindingFor(p)) {
                    ForEach(0..<options.count, id: \.self) { i in
                        Text(options[i]).tag(i)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .opacity(isTouched ? 1.0 : 0.55)
            default:
                Slider(
                    value: doubleBindingFor(p),
                    in: Double(p.range.lowerBound)...Double(p.range.upperBound),
                    step: 1
                )
                .opacity(isTouched ? 1.0 : 0.45)
                // Right-click → "Reset". SwiftUI's Slider eats tap gestures
                // (incl. simultaneousGesture), so a context menu is the only
                // reliable way to surface a reset action.
                .contextMenu {
                    Button("Reset to default") { resetParameter(p) }
                }

                Text(isTouched
                     ? formatted(value: values[p.stableID] ?? 0, format: p.format)
                     : "—")
                    .font(.system(size: 10.5, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(isTouched ? .secondary : .tertiary)
                    .contextMenu {
                        Button("Reset to default") { resetParameter(p) }
                    }
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 4)
    }

    /// Reset a parameter to its midpoint and re-send the CC. Once the
    /// byte-offset map exists, "midpoint" will become "the voice's stored
    /// value at editor open".
    private func resetParameter(_ p: VoiceParameter) {
        let mid = (p.range.lowerBound + p.range.upperBound) / 2
        values[p.stableID] = mid
        touched.remove(p.stableID)
        Task { await controller.setParameter(p, value: mid) }
    }

    // MARK: Probe section

    @ViewBuilder
    private var probeSection: some View {
        DisclosureGroup(isExpanded: $probeExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Button("Set baseline") {
                        probeBaseline = currentVoice?.record
                        probeCurrent = nil
                        probeError = nil
                    }
                    .controlSize(.small)
                    .disabled(currentVoice == nil)

                    Button(probeReading ? "Reading…" : "Re-read from device") {
                        Task { await rereadFromDevice() }
                    }
                    .controlSize(.small)
                    .disabled(probeReading)

                    Spacer()
                    if let err = probeError {
                        Text(err)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red)
                    } else if let bl = probeBaseline, let cur = probeCurrent {
                        let diffCount = zip(bl, cur).filter { $0 != $1 }.count
                        Text("\(diffCount) byte\(diffCount == 1 ? "" : "s") changed")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(diffCount > 0 ? .orange : .secondary)
                    }
                }
                Text("Reading device index \(probeDeviceIndex) (bank: \(bank.kind.rawValue), slot: \(slot))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if let bytes = probeCurrent ?? probeBaseline {
                    hexGrid(bytes: bytes, baseline: probeBaseline)
                } else {
                    Text("Tap Set baseline to capture the loaded voice bytes, move a slider, then Re-read from device.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if bank.kind == .user, let baseline = probeBaseline {
                    Divider()
                    writeProbeRow(baseline: baseline)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
        } label: {
            Text("Byte Probe")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func hexGrid(bytes: [UInt8], baseline: [UInt8]?) -> some View {
        let cols = 8
        VStack(alignment: .leading, spacing: 1) {
            ForEach(0..<(bytes.count + cols - 1) / cols, id: \.self) { row in
                HStack(spacing: 3) {
                    Text(String(format: "%02X:", row * cols))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, alignment: .leading)
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        if idx < bytes.count {
                            let changed = baseline != nil && baseline![idx] != bytes[idx]
                            Text(String(format: "%02X", bytes[idx]))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(changed ? Color.orange : .secondary)
                                .background(changed ? Color.orange.opacity(0.15) : .clear,
                                            in: RoundedRectangle(cornerRadius: 2))
                                .frame(width: 22)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func writeProbeRow(baseline: [UInt8]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Write probe — overwrites slot \(slot) on device")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
            HStack(spacing: 6) {
                Text("Byte \(probeByteIndex)")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 54, alignment: .leading)
                Stepper("", value: $probeByteIndex, in: 9...63)
                    .labelsHidden()
                Text(String(format: "now: %02X", baseline[probeByteIndex]))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("→ 00") { Task { await writeProbe(baseline: baseline, value: 0x00) } }
                    .controlSize(.small)
                    .disabled(probeWriting)
                Button("→ 7F") { Task { await writeProbe(baseline: baseline, value: 0x7F) } }
                    .controlSize(.small)
                    .disabled(probeWriting)
                Button("Restore") { Task { await writeProbe(baseline: baseline, value: nil) } }
                    .controlSize(.small)
                    .disabled(probeWriting)
            }
        }
    }

    private func writeProbe(baseline: [UInt8], value: UInt8?) async {
        probeWriting = true
        probeError = nil
        defer { probeWriting = false }
        var record = baseline
        if let v = value { record[probeByteIndex] = v }
        do {
            try await controller.writeRawRecord(userSlot: slot, record: record)
        } catch {
            probeError = "Write failed: \(error)"
        }
    }

    private var probeDeviceIndex: Int {
        switch bank.kind {
        case .user:                  return 384 + slot
        case .factory, .temporary:   return slot
        }
    }

    private func rereadFromDevice() async {
        probeReading = true
        probeError = nil
        defer { probeReading = false }
        do {
            probeCurrent = try await controller.readRawRecord(deviceIndex: probeDeviceIndex)
        } catch {
            probeError = "Failed: \(error)"
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                // Reset to mid-range. Save/revert come back when byte-offset map exists.
                for p in VoiceParameters.all {
                    values[p.stableID] = (p.range.lowerBound + p.range.upperBound) / 2
                }
            } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }
            .controlSize(.small)
            Spacer()
            Button {
                // Save is intentionally gated until Phase 7.1 byte-offset map is done.
            } label: {
                Label("Save", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(true)
            .help("Save will be enabled once the byte-offset map is finalized (Phase 7.1).")
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(.background.secondary)
    }

    // MARK: Bindings

    private func bindingFor(_ p: VoiceParameter) -> Binding<Int> {
        Binding(
            get: { values[p.stableID] ?? p.range.lowerBound },
            set: { newValue in
                let clamped = min(max(newValue, p.range.lowerBound), p.range.upperBound)
                values[p.stableID] = clamped
                touched.insert(p.stableID)
                Task { await controller.setParameter(p, value: clamped) }
            }
        )
    }

    private func doubleBindingFor(_ p: VoiceParameter) -> Binding<Double> {
        Binding(
            get: { Double(values[p.stableID] ?? p.range.lowerBound) },
            set: { newValue in
                let v = Int(newValue.rounded())
                let clamped = min(max(v, p.range.lowerBound), p.range.upperBound)
                if values[p.stableID] != clamped {
                    values[p.stableID] = clamped
                    touched.insert(p.stableID)
                    Task { await controller.setParameter(p, value: clamped) }
                }
            }
        )
    }

    // MARK: Helpers

    private var currentVoice: Voice? {
        guard slot >= 0 && slot < bank.voices.count else { return nil }
        return bank.voices[slot]
    }

    private var slotPrefix: String {
        switch bank.kind {
        case .user:      return "U"
        case .temporary: return "T"
        case .factory:   return "F"
        }
    }

    private func formatted(value: Int, format: ValueFormat) -> String {
        switch format {
        case .signed:    return value >= 0 ? "+\(value)" : "\(value)"
        case .unsigned:  return "\(value)"
        case .menu:      return ""
        }
    }
}
