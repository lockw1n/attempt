import Foundation
import PowerliftingCore
import SwiftData

/// One logged set (`TR-0.3.4`).
///
/// **``isWarmup`` and ``isCompleted`` are required by `init`, and that is where `G-1.8` is
/// enforced** — as on `SetRecord`, which gives them no default argument either. Their schema default
/// is `G-2.5`'s concession and is not a claim about the set; see ``SchemaDefaults``.
@Model
final class SetEntryEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``ExerciseEntryEntity`` this set belongs to.
    var entryID: UUID = SchemaDefaults.unlinkedID

    /// Position within the entry, ascending. The third key a chronological sort uses, after the
    /// session's date and the entry's own order.
    var order: Int = 0

    /// The load on **one** implement, in grams (`G-1.1`, `TR-0.2.3`): a barbell set stores the whole
    /// bar, two 40 kg dumbbells store 40. Signed on purpose — assisted work is a negative added load.
    var weightGrams: Int = 0

    /// Repetitions performed, as entered. Whether they count per side is the exercise's laterality.
    var reps: Int = 0

    /// Rating of perceived exertion, 1…10, or `nil`. Stored unvalidated; `SetRecord` enforces the
    /// bound at the domain boundary.
    var rpe: Double?

    /// Reps in reserve, 0…9, or `nil`, and stored unvalidated as ``rpe`` is. Independent of it —
    /// `G-1.6` forbids rewriting one to agree with the other, so the two may contradict.
    var rir: Int?

    /// Whether this was a warmup rather than a working set (`G-1.8`). Required at `init`.
    var isWarmup: Bool = SchemaDefaults.isWarmup

    /// Whether the set was actually performed (`G-1.8`). A prescribed-but-unperformed set carries
    /// its targets and `false`. Required at `init`.
    var isCompleted: Bool = SchemaDefaults.isCompleted

    /// What was prescribed, in grams (`G-1.1`), against what ``weightGrams`` records was done.
    var targetWeightGrams: Int?

    /// See ``targetWeightGrams``.
    var targetReps: Int?

    /// Modifier spellings, deduplicated and sorted (`FR-1.2.8`, `TR-0.2.3`).
    ///
    /// **An unrecognised spelling is kept verbatim, never degraded** — the opposite of this module's
    /// vocabulary columns, because nothing re-supplies a modifier the user logged. The canonical
    /// order is a storage contract rather than a convenience: it is what makes two sets with the
    /// same modifiers compare and encode alike. `private(set)` because a documented ordering rule is
    /// one a caller can break silently — write through ``replaceModifiers(with:)``.
    private(set) var modifiers: [String] = []

    var notes: String = ""

    /// When the set was completed, if it was tracked live. Not a substitute for the session's date:
    /// this is `nil` on every imported or after-the-fact entry.
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        entryID: UUID,
        order: Int,
        weightGrams: Int,
        reps: Int,
        isWarmup: Bool,
        isCompleted: Bool,
        rpe: Double? = nil,
        rir: Int? = nil,
        targetWeightGrams: Int? = nil,
        targetReps: Int? = nil,
        modifiers: [SetModifier] = [],
        notes: String = "",
        completedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.entryID = entryID
        self.order = order
        self.weightGrams = weightGrams
        self.reps = reps
        self.isWarmup = isWarmup
        self.isCompleted = isCompleted
        self.rpe = rpe
        self.rir = rir
        self.targetWeightGrams = targetWeightGrams
        self.targetReps = targetReps
        self.modifiers = Self.canonicalised(modifiers.map(\.rawValue))
        self.notes = notes
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Replaces the modifier list, canonicalising it. The only way to write ``modifiers``.
    ///
    /// Takes raw spellings rather than `SetModifier` because a caller reading them back out of the
    /// store has strings, and an unrecognised one has to survive that round trip.
    func replaceModifiers(with raw: [String]) {
        modifiers = Self.canonicalised(raw)
    }

    /// `raw` deduplicated and sorted by spelling. See ``modifiers``.
    static func canonicalised(_ raw: [String]) -> [String] {
        Set(raw).sorted()
    }
}
