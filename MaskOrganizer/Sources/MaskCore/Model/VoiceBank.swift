import Foundation
import Observation

/// A reorderable collection of voices. Read-only kinds (factory) reject mutation.
@Observable
public final class VoiceBank: @unchecked Sendable {
    public enum Kind: String, Codable {
        case factory   // read-only on the device
        case user      // read/write
        case temporary // working pane (matches the web app's left pane)
    }

    public let kind: Kind
    /// Maximum slot count for this bank kind. Factory: 377, user: 200, temporary: 377.
    public let capacity: Int
    public private(set) var voices: [Voice]

    public init(kind: Kind, capacity: Int? = nil, voices: [Voice] = []) {
        self.kind = kind
        self.capacity = capacity ?? Self.defaultCapacity(for: kind)
        self.voices = voices
    }

    public static func defaultCapacity(for kind: Kind) -> Int {
        switch kind {
        case .factory:   return 377
        case .user:      return 200
        case .temporary: return 377
        }
    }

    public var isReadOnly: Bool { kind == .factory }

    /// Replace the entire bank atomically.
    public func replaceAll(_ newVoices: [Voice]) {
        voices = newVoices
    }

    /// Move a set of slots to a destination index (SwiftUI `move(fromOffsets:toOffset:)` semantics).
    public func move(_ indices: IndexSet, to destination: Int) {
        guard !isReadOnly else { return }
        let moved = indices.map { voices[$0] }
        let dest = destination - indices.filter { $0 < destination }.count
        var remaining = voices
        for i in indices.sorted(by: >) { remaining.remove(at: i) }
        remaining.insert(contentsOf: moved, at: max(0, min(dest, remaining.count)))
        voices = remaining
        reindex()
    }

    /// Shift the voice at `slot` up (delta = -1) or down (delta = +1) by one
    /// position. No-op if it would move past either end. Returns the new slot.
    @discardableResult
    public func shift(_ slot: Int, by delta: Int) -> Int {
        guard !isReadOnly else { return slot }
        guard slot >= 0 && slot < voices.count else { return slot }
        let newSlot = slot + delta
        guard newSlot >= 0 && newSlot < voices.count else { return slot }
        voices.swapAt(slot, newSlot)
        reindex()
        return newSlot
    }

    /// Insert or overwrite a voice at a slot.
    public func upsert(_ voice: Voice, at slot: Int) {
        guard !isReadOnly else { return }
        if slot < voices.count {
            voices[slot] = voice
            voices[slot].index = slot
        } else {
            var v = voice
            v.index = voices.count
            voices.append(v)
        }
    }

    /// Remove voices at the given slots. Throws on read-only banks.
    public func remove(at slots: IndexSet) throws {
        guard !isReadOnly else {
            throw VoiceBankError.readOnlyBank
        }
        for i in slots.sorted(by: >) { voices.remove(at: i) }
        reindex()
    }

    /// Rename the voice at `slot`. Stores as `displayNameOverride` so the
    /// underlying record bytes aren't touched until export/send time.
    public func rename(at slot: Int, to name: String) throws {
        guard !isReadOnly else { throw VoiceBankError.readOnlyBank }
        guard slot < voices.count else { throw VoiceBankError.slotOutOfRange(slot) }
        voices[slot].displayNameOverride = name
    }

    private func reindex() {
        for i in 0..<voices.count { voices[i].index = i }
    }
}

public enum VoiceBankError: Swift.Error, Equatable {
    case readOnlyBank
    case slotOutOfRange(Int)
    case capacityExceeded
}
