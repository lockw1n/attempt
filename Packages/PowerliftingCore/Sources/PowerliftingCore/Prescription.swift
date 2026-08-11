/// What a program slot prescribes as *load* (`TR-0.2.10`).
///
/// A prescription says how heavy, never how many: set count and rep count belong to the slot
/// (`FR-2.2.2`). ``amrap`` is the one case that reads as a rep instruction, and it carries no load
/// for exactly that reason — see its own note.
///
/// **Nothing here is validated at construction.** A percentage may be zero, negative or `NaN`, and
/// an RPE may be 47. The ranges a payload has to fall in to *resolve* are stated once, here rather
/// than on each case: every percentage is a dimensionless ratio, finite and greater than zero and
/// uncapped above — 1.1 is a peaking block, not an error — and an RPE is on ``SetRecord/rpeRange``'s
/// scale of 1 through 10. Values outside them are *refusals at resolution*
/// (`TR-0.2.11`), which is where a caller can be told which input was impossible — the same split
/// ``TrainingMaxSource/percentOfRepMax(reps:)`` makes, and an enum case cannot be failable in any
/// event. One consequence is worth stating: a `NaN` percentage makes a value that does not equal
/// itself, because `Double`'s equality is the one in play.
public enum Prescription: Sendable, Hashable {
    /// An absolute load. The number on the bar, whatever anything else says.
    case fixedWeight(Weight)

    /// A fraction of the exercise's training max — `0.85` is 85%, not `85`.
    ///
    /// A training max has already been through a rounding rule, so a weight prescribed this way is
    /// two roundings from the e1RM it derives from. Both steps are real and neither is redundant.
    case percentOfTrainingMax(percentage: Double)

    /// A fraction of the exercise's best estimated one-rep maximum, as a ratio.
    case percentOfE1RM(percentage: Double)

    /// A fraction of the heaviest set worked up to in this session, as a ratio.
    ///
    /// The backoff half of `FR-2.2.3`. Unlike the other two percentages, it resolves against
    /// something inside the same session rather than against stored history.
    case percentOfTopSet(percentage: Double)

    /// A target effort rather than a target load: work up until the set feels this hard.
    ///
    /// Resolving it needs a rep count, which the slot supplies. The scale is
    /// ``SetRecord/rpeRange``'s, and this type does not restate it.
    case rpeTarget(rpe: Double)

    /// As many reps as possible, at a load this prescription does not specify.
    ///
    /// **It carries nothing on purpose.** AMRAP is an instruction about reps, and reps live on the
    /// slot (`FR-2.2.2`); giving it a load would make it a wrapper around one of the other cases
    /// and make prescriptions recursive. A slot that prescribes both a load and an open rep count
    /// is expressing that with its rep field, not here.
    case amrap

    /// Last session's load for this slot plus a step. Signed: a negative step is a configured
    /// deload, not a mistake.
    case previousPlusIncrement(Weight)

    /// Bodyweight work, with `added` as the *external* load only — matching what a set records.
    ///
    /// Zero is plain bodyweight and a negative value is assistance (a banded pull-up). The user's
    /// bodyweight is not part of this number and is not needed to resolve it.
    case bodyweight(added: Weight)

    /// A prescription from a newer app version, preserved rather than interpreted (`NFR-2.3`).
    ///
    /// Only a decoder produces this case; ``UnrecognisedPrescription`` refuses to hold a type this
    /// version knows, so it can never shadow one of the cases above.
    case unrecognised(UnrecognisedPrescription)

    /// The schema version this version writes (`TR-2.4`). See ``Prescription/init(from:)`` for what
    /// reading a different one does.
    public static let currentSchemaVersion = 1

    /// Whether this value is a prescription this version can act on.
    ///
    /// `false` only for ``unrecognised(_:)``. `FR-2.3.5` needs the distinction: an unresolvable
    /// prescription has to produce a prompt rather than a zero.
    public var isRecognised: Bool {
        kind != nil
    }

    /// The wire discriminator for this value, or `nil` when it is ``unrecognised(_:)`` and the
    /// discriminator is a string this version does not know.
    var kind: PrescriptionKind? {
        switch self {
        case .fixedWeight: .fixedWeight
        case .percentOfTrainingMax: .percentOfTrainingMax
        case .percentOfE1RM: .percentOfE1RM
        case .percentOfTopSet: .percentOfTopSet
        case .rpeTarget: .rpeTarget
        case .amrap: .amrap
        case .previousPlusIncrement: .previousPlusIncrement
        case .bodyweight: .bodyweight
        case .unrecognised: nil
        }
    }
}

/// The prescription types this version recognises, as their persisted spellings.
///
/// **Renaming a case is a storage migration**, and reusing a spelling for different meaning is
/// worse than one: a decoder treats a known spelling as readable no matter which version wrote it,
/// so a changed meaning would be read as the old one. A new meaning gets a new spelling.
///
/// Not `Codable`, and not the persisted type: an unrecognised spelling has to reach
/// ``UnrecognisedPrescription``, and a `Codable` enum would have thrown before it could.
enum PrescriptionKind: String, CaseIterable {
    case fixedWeight
    case percentOfTrainingMax
    case percentOfE1RM
    case percentOfTopSet
    case rpeTarget
    case amrap
    case previousPlusIncrement
    case bodyweight
}
