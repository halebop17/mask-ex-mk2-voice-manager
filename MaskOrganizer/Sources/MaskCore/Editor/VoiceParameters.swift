import Foundation

/// Static voice parameter table — derived from the Mask1EX MK2 manual
/// (pp. 39–42). Used by the editor view to render sliders/pickers and by the
/// CC live-send code path.
///
/// `byteOffset` on each entry is `nil` until Phase 7.1's audio-probe pass
/// nails down the byte layout. Until then, the editor lets you audition
/// changes (CC live-send) but Save is disabled.
public enum VoiceParameters {

    /// All editable parameters, in the order they should appear in the UI.
    /// Grouping comes from `ParameterGroup` (sections in the editor pane).
    public static let all: [VoiceParameter] = general
        + osc1 + osc2
        + noise
        + filter
        + lfo1 + lfo2
        + pitch
        + arp
        + fx
        + global

    public static func parameters(in group: ParameterGroup) -> [VoiceParameter] {
        all.filter { $0.group == group }
    }

    public static func parameter(withID id: String) -> VoiceParameter? {
        all.first { $0.stableID == id }
    }

    // MARK: - Sections

    private static let general: [VoiceParameter] = [
        .init(stableID: "general.volume",        group: .general, displayName: "Volume",      cc:  7, format: .unsigned(0...127)),
        .init(stableID: "general.panSpread",     group: .general, displayName: "Pan Spread",  cc:  3, format: .unsigned(0...127)),
        .init(stableID: "general.transpose",     group: .general, displayName: "Transpose",   cc:  9, format: .signed(-64...63)),
        .init(stableID: "general.portamento",    group: .general, displayName: "Portamento",  cc: 84, format: .unsigned(0...127)),
    ]

    private static let osc1: [VoiceParameter] = [
        .init(stableID: "osc1.semi",       group: .osc1, displayName: "Semi",          cc: 29, format: .signed(-24...24)),
        .init(stableID: "osc1.tune",       group: .osc1, displayName: "Tune",          cc: 14, format: .signed(-64...63)),
        .init(stableID: "osc1.mask",       group: .osc1, displayName: "Mask",          cc: 23, extraCCs: [94, 46, 48], format: .unsigned(0...511)),
        .init(stableID: "osc1.envLevel",   group: .osc1, displayName: "Env Level",     cc: 25, format: .unsigned(0...127)),
        .init(stableID: "osc1.envAttack",  group: .osc1, displayName: "Env Attack",    cc: 103, format: .unsigned(0...127)),
        .init(stableID: "osc1.envDecay",   group: .osc1, displayName: "Env Decay",     cc: 107, format: .unsigned(0...127)),
        .init(stableID: "osc1.envSustain", group: .osc1, displayName: "Env Sustain",   cc: 111, format: .unsigned(0...127)),
        .init(stableID: "osc1.envRelease", group: .osc1, displayName: "Env Release",   cc: 115, format: .unsigned(0...127)),
        .init(stableID: "osc1.maskStart",  group: .osc1, displayName: "Mask Δ Start",  cc: 52, format: .unsigned(0...127)),
        .init(stableID: "osc1.maskSpeed",  group: .osc1, displayName: "Mask Δ Speed",  cc: 54, format: .unsigned(0...127)),
        .init(stableID: "osc1.maskLoop",   group: .osc1, displayName: "Mask Δ Loop",   cc: 56, format: .menu(["Off", "Forward", "Bidirectional"])),
    ]

    private static let osc2: [VoiceParameter] = [
        .init(stableID: "osc2.semi",       group: .osc2, displayName: "Semi",          cc: 30, format: .signed(-24...24)),
        .init(stableID: "osc2.tune",       group: .osc2, displayName: "Tune",          cc: 15, format: .signed(-64...63)),
        .init(stableID: "osc2.mask",       group: .osc2, displayName: "Mask",          cc: 24, extraCCs: [95, 47, 49], format: .unsigned(0...511)),
        .init(stableID: "osc2.envLevel",   group: .osc2, displayName: "Env Level",     cc: 26, format: .unsigned(0...127)),
        .init(stableID: "osc2.envAttack",  group: .osc2, displayName: "Env Attack",    cc: 104, format: .unsigned(0...127)),
        .init(stableID: "osc2.envDecay",   group: .osc2, displayName: "Env Decay",     cc: 108, format: .unsigned(0...127)),
        .init(stableID: "osc2.envSustain", group: .osc2, displayName: "Env Sustain",   cc: 112, format: .unsigned(0...127)),
        .init(stableID: "osc2.envRelease", group: .osc2, displayName: "Env Release",   cc: 116, format: .unsigned(0...127)),
        .init(stableID: "osc2.maskStart",  group: .osc2, displayName: "Mask Δ Start",  cc: 53, format: .unsigned(0...127)),
        .init(stableID: "osc2.maskSpeed",  group: .osc2, displayName: "Mask Δ Speed",  cc: 55, format: .unsigned(0...127)),
        .init(stableID: "osc2.maskLoop",   group: .osc2, displayName: "Mask Δ Loop",   cc: 57, format: .menu(["Off", "Forward", "Bidirectional"])),
    ]

    private static let noise: [VoiceParameter] = [
        .init(stableID: "noise.frequency",  group: .noise, displayName: "Frequency",     cc: 31, format: .unsigned(0...127)),
        .init(stableID: "noise.tracking",   group: .noise, displayName: "Kbd Tracking",  cc: 50, format: .unsigned(0...127)),
        .init(stableID: "noise.envLevel",   group: .noise, displayName: "Env Level",    cc: 28, format: .unsigned(0...127)),
        .init(stableID: "noise.envAttack",  group: .noise, displayName: "Env Attack",   cc: 106, format: .unsigned(0...127)),
        .init(stableID: "noise.envDecay",   group: .noise, displayName: "Env Decay",    cc: 110, format: .unsigned(0...127)),
        .init(stableID: "noise.envSustain", group: .noise, displayName: "Env Sustain",  cc: 114, format: .unsigned(0...127)),
        .init(stableID: "noise.envRelease", group: .noise, displayName: "Env Release",  cc: 118, format: .unsigned(0...127)),
    ]

    private static let filter: [VoiceParameter] = [
        .init(stableID: "filter.cutoff",     group: .filter, displayName: "Cutoff",       cc: 20, format: .unsigned(0...127)),
        .init(stableID: "filter.resonance",  group: .filter, displayName: "Resonance",    cc: 21, format: .unsigned(0...127)),
        .init(stableID: "filter.mode",       group: .filter, displayName: "Mode",         cc: 22, format: .menu(["Low Pass", "High Pass", "Band Pass", "Notch"])),
        .init(stableID: "filter.tracking",   group: .filter, displayName: "Tracking",     cc: 19, format: .unsigned(0...127)),
        .init(stableID: "filter.extra",      group: .filter, displayName: "Extra",        cc: 51, format: .unsigned(0...127)),
        .init(stableID: "filter.envLevel",   group: .filter, displayName: "Env Level",    cc: 27, format: .signed(-64...63)),
        .init(stableID: "filter.envAttack",  group: .filter, displayName: "Env Attack",   cc: 105, format: .unsigned(0...127)),
        .init(stableID: "filter.envDecay",   group: .filter, displayName: "Env Decay",    cc: 109, format: .unsigned(0...127)),
        .init(stableID: "filter.envSustain", group: .filter, displayName: "Env Sustain",  cc: 113, format: .unsigned(0...127)),
        .init(stableID: "filter.envRelease", group: .filter, displayName: "Env Release",  cc: 117, format: .unsigned(0...127)),
    ]

    private static let lfo1: [VoiceParameter] = [
        .init(stableID: "lfo1.destination", group: .lfo1, displayName: "Destination", cc: 33, format: .menu(lfoDestinations)),
        .init(stableID: "lfo1.waveform",    group: .lfo1, displayName: "Waveform",    cc: 35, format: .menu(lfoWaveforms)),
        .init(stableID: "lfo1.amount",      group: .lfo1, displayName: "Amount",      cc: 85, format: .signed(-64...63)),
        .init(stableID: "lfo1.speed",       group: .lfo1, displayName: "Speed",       cc: 87, format: .unsigned(0...127)),
        .init(stableID: "lfo1.delay",       group: .lfo1, displayName: "Delay",       cc: 37, format: .unsigned(0...127)),
        .init(stableID: "lfo1.decay",       group: .lfo1, displayName: "Decay",       cc: 39, format: .unsigned(0...127)),
    ]

    private static let lfo2: [VoiceParameter] = [
        .init(stableID: "lfo2.destination", group: .lfo2, displayName: "Destination", cc: 34, format: .menu(lfoDestinations)),
        .init(stableID: "lfo2.waveform",    group: .lfo2, displayName: "Waveform",    cc: 36, format: .menu(lfoWaveforms)),
        .init(stableID: "lfo2.amount",      group: .lfo2, displayName: "Amount",      cc: 86, format: .signed(-64...63)),
        .init(stableID: "lfo2.speed",       group: .lfo2, displayName: "Speed",       cc: 88, format: .unsigned(0...127)),
        .init(stableID: "lfo2.delay",       group: .lfo2, displayName: "Delay",       cc: 38, format: .unsigned(0...127)),
        .init(stableID: "lfo2.decay",       group: .lfo2, displayName: "Decay",       cc: 40, format: .unsigned(0...127)),
    ]

    private static let pitch: [VoiceParameter] = [
        .init(stableID: "pitch.start", group: .pitch, displayName: "Start", cc: 41, format: .signed(-64...63)),
        .init(stableID: "pitch.speed", group: .pitch, displayName: "Speed", cc: 42, format: .unsigned(0...127)),
        .init(stableID: "pitch.end",   group: .pitch, displayName: "End",   cc: 43, format: .signed(-64...63)),
    ]

    private static let arp: [VoiceParameter] = [
        .init(stableID: "arp.type",  group: .arp, displayName: "Type",  cc: 119, format: .menu(arpTypes)),
        .init(stableID: "arp.speed", group: .arp, displayName: "Speed", cc:  89, format: .unsigned(0...127)),
    ]

    private static let fx: [VoiceParameter] = [
        .init(stableID: "fx.fx1Type",    group: .fx, displayName: "FX1 Type",    cc: 92, format: .menu(fxTypes)),
        .init(stableID: "fx.fx1Balance", group: .fx, displayName: "FX1 Balance", cc: 90, format: .unsigned(0...127)),
        .init(stableID: "fx.fx2Type",    group: .fx, displayName: "FX2 Type",    cc: 93, format: .menu(fxTypes)),
        .init(stableID: "fx.fx2Balance", group: .fx, displayName: "FX2 Balance", cc: 91, format: .unsigned(0...127)),
    ]

    private static let global: [VoiceParameter] = [
        .init(stableID: "global.playMode",       group: .global, displayName: "Play Mode",       cc: 44, format: .menu(playModes)),
        .init(stableID: "global.envRateScaling", group: .global, displayName: "Env Rate Scale", cc: 45, format: .unsigned(0...127)),
    ]

    // MARK: - Enum option labels (placeholder — refine once verified on hardware)

    private static let lfoWaveforms = [
        "Sine", "Triangle", "Saw Up", "Saw Down", "Square", "S&H", "Noise", "Random",
    ]
    private static let lfoDestinations = [
        "Off", "Pitch", "Filter", "Volume", "Pan", "Osc1 Mask", "Osc2 Mask", "Noise", "FX1", "FX2",
    ]
    private static let arpTypes = [
        "Off", "Up", "Down", "Up/Down", "Random", "As Played",
    ]
    private static let fxTypes = [
        "Off", "Reverb", "Delay", "Chorus", "Flanger", "Phaser", "Distortion", "Bitcrusher",
    ]
    private static let playModes = [
        "Poly", "Mono", "Legato", "Layer", "Split",
    ]
}
