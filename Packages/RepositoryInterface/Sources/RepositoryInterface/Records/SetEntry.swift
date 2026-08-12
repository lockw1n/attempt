import Foundation
import PowerliftingCore

/// One logged set (`TR-0.3.4`).
///
/// **This is not `SetRecord` and must not embed one.** `SetRecord` is the analytical value type the
/// formulas read and it validates — an RPE outside 1…10 is rejected at its initialiser, where this
/// column is stored unvalidated. A record that embedded it could not represent a set carrying a
/// value from a newer version, so the read would refuse and the user would lose the set rather than
/// the field. `SetRecord` also has no ``id``, ``order``, targets, ``notes`` or ``completedAt``:
/// `FR-1.2.3`'s per-set note exists only on this side. The projection into `SetRecord`, and what it
/// refuses, is T-0.41's.
public struct SetEntry: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``ExerciseEntry`` this set belongs to.
    public let entryID: UUID

    /// Position within the entry, ascending. Zero-based, and the third key of the chronological
    /// order.
    public let order: Int

    /// The load on **one** implement (`TR-0.2.3`): a barbell set carries the whole bar, two 40 kg
    /// dumbbells carry 40. Signed, because assisted work is a negative added load.
    public let weight: Weight

    /// Repetitions performed. Zero or more, and **unchecked here** as ``rpe`` is — a failed set
    /// records zero (`FR-1.2.5`), and a negative one is what a foreign row looks like. Whether they
    /// count per side is the exercise's laterality.
    public let reps: Int

    /// Rating of perceived exertion, or `nil`. The scale is 1…10 and **this is not checked here**;
    /// a value outside it is what a foreign row looks like.
    public let rpe: Double?

    /// Reps in reserve, or `nil`, unchecked as ``rpe`` is. The scale is 0…9. Independent of
    /// ``rpe`` — `G-1.6` forbids rewriting one to agree with the other, so the two may contradict.
    public let rir: Int?

    /// Whether this was a warmup rather than a working set (`G-1.8`).
    public let isWarmup: Bool

    /// Whether the set was actually performed (`G-1.8`). A prescribed-but-unperformed set carries
    /// its targets and `false`.
    public let isCompleted: Bool

    /// What was prescribed, against what ``weight`` records was done.
    public let targetWeight: Weight?

    /// The prescribed repetitions. Zero or more, unchecked as ``reps`` is. See ``targetWeight``.
    public let targetReps: Int?

    /// Modifier spellings (`FR-1.2.8`), deduplicated and sorted by raw spelling.
    ///
    /// **Canonicalised by the initialiser, not merely documented.** The stored column is canonical
    /// and its only writer canonicalises, so a record that kept what a caller handed it would
    /// compare unequal to the same set read back — and belt+sleeves would be a different record
    /// from sleeves+belt. This is the one property any record initialiser normalises; that
    /// initialiser says why it is not a breach of the no-validation rule.
    ///
    /// **An unrecognised spelling survives verbatim**, which is what `SetModifier` being an open
    /// vocabulary buys: nothing re-supplies a modifier the user configured, so degrading one would
    /// destroy the only copy. A mapping to `[SetModifierTerm]` would do exactly that.
    public let modifiers: [SetModifier]

    /// The per-set note (`FR-1.2.3`).
    public let notes: String

    /// When the set was completed, if it was tracked live. `nil` on every imported or
    /// after-the-fact entry, so it is not a substitute for the session's date.
    public let completedAt: Date?

    /// Creates a set record.
    ///
    /// ``isWarmup`` and ``isCompleted`` take no default argument, on either side of the boundary
    /// (`G-1.8`): a defaulted flag is the ambiguity the requirement exists to prevent, and the
    /// stored column's default is a CloudKit concession rather than a claim about the set.
    ///
    /// **`modifiers` is canonicalised here — deduplicated and sorted by raw spelling — and it is
    /// the only normalisation any record initialiser performs.** It is not the validation this
    /// layer refuses to do: nothing is rejected and no spelling is altered, so a corrupt row still
    /// round-trips. What it prevents is a *second* ordering authority, since the stored column is
    /// canonical and its only writer canonicalises. Without it two records describing one set
    /// compare unequal, and a fake that stores what it is handed would disagree with the store on
    /// read-back — a divergence a shared conformance suite is supposed to catch and would instead
    /// inherit.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        entryID: UUID,
        order: Int,
        weight: Weight,
        reps: Int,
        rpe: Double?,
        rir: Int?,
        isWarmup: Bool,
        isCompleted: Bool,
        targetWeight: Weight?,
        targetReps: Int?,
        modifiers: [SetModifier],
        notes: String,
        completedAt: Date?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.entryID = entryID
        self.order = order
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.rir = rir
        self.isWarmup = isWarmup
        self.isCompleted = isCompleted
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.modifiers = Set(modifiers).sorted { $0.rawValue < $1.rawValue }
        self.notes = notes
        self.completedAt = completedAt
    }
}
