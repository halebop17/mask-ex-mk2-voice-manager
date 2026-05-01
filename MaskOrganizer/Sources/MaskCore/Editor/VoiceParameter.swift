import Foundation

/// One editable voice parameter — what the user sees as a slider or picker.
///
/// `cc` is the primary MIDI CC# (per the Mask1EX MK2 manual pp. 39–42) used for
/// live audition while editing. Some parameters (the 9-bit oscillator masks)
/// span four CC numbers, one per 128-value page; `extraCCs` carries the rest
/// in order.
///
/// `byteOffset` will be filled in by Phase 7.1's audio-probe pass; until then
/// it is `nil` and Save is gated.
public struct VoiceParameter: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { stableID }
    public let stableID: String                     // e.g. "filter.cutoff"
    public let group: ParameterGroup
    public let displayName: String
    public let cc: UInt8                            // primary CC for live send
    public let extraCCs: [UInt8]                    // for masks: the 3 other page CCs
    public let format: ValueFormat
    public let byteOffset: Int?                     // 9...63 once known; nil = save disabled

    public init(
        stableID: String,
        group: ParameterGroup,
        displayName: String,
        cc: UInt8,
        extraCCs: [UInt8] = [],
        format: ValueFormat,
        byteOffset: Int? = nil
    ) {
        self.stableID = stableID
        self.group = group
        self.displayName = displayName
        self.cc = cc
        self.extraCCs = extraCCs
        self.format = format
        self.byteOffset = byteOffset
    }

    /// Human-readable range bounds for the UI.
    public var range: ClosedRange<Int> { format.range }

    /// Convert the user-facing value (e.g. -64…+63 for signed) to the on-wire CC pair.
    /// Returns the (CC#, 7-bit value) to actually send. For masks, the right
    /// page's CC is selected based on which 128-value bucket `value` falls in.
    public func ccMessage(for value: Int) -> (cc: UInt8, value: UInt8) {
        let stored = format.userToStored(value)
        if extraCCs.isEmpty {
            return (cc, UInt8(clamping: stored))
        }
        // Multi-page (mask). Determine the page from the stored value.
        let allCCs = [cc] + extraCCs
        let page = min(allCCs.count - 1, max(0, stored / 128))
        let pageValue = stored % 128
        return (allCCs[page], UInt8(pageValue))
    }
}

// MARK: - Groups

public enum ParameterGroup: String, CaseIterable, Sendable {
    case general = "General"
    case osc1    = "Osc1"
    case osc2    = "Osc2"
    case noise   = "Noise"
    case filter  = "Filter"
    case lfo1    = "LFO1"
    case lfo2    = "LFO2"
    case pitch   = "Pitch"
    case arp     = "Arp"
    case fx      = "FX"
    case global  = "Global"

    public var displayName: String { rawValue }
}

// MARK: - Value formats

public enum ValueFormat: Equatable, Hashable, Sendable {
    /// Plain unsigned slider, range typically `0...127`.
    case unsigned(ClosedRange<Int>)
    /// Signed slider, displayed `-N…+N`. Stored as `0…2N` with center at `N`.
    /// e.g. `signed(-64...63)` is stored 0…127 with 64 = zero.
    case signed(ClosedRange<Int>)
    /// Discrete enum (filter mode, LFO waveform, FX type, etc.).
    case menu([String])

    /// User-visible range (for display labels and slider bounds).
    public var range: ClosedRange<Int> {
        switch self {
        case .unsigned(let r):       return r
        case .signed(let r):         return r
        case .menu(let options):     return 0...(options.count - 1)
        }
    }

    /// Map a user-visible value to the byte/CC value.
    public func userToStored(_ user: Int) -> Int {
        switch self {
        case .unsigned: return user
        case .signed(let r):
            // Storage = user - r.lowerBound  → e.g. -64 → 0, 0 → 64, +63 → 127.
            return user - r.lowerBound
        case .menu: return user
        }
    }

    /// Inverse of `userToStored`.
    public func storedToUser(_ stored: Int) -> Int {
        switch self {
        case .unsigned: return stored
        case .signed(let r):
            return stored + r.lowerBound
        case .menu: return stored
        }
    }
}
