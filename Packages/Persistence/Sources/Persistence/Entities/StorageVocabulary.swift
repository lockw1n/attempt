// Three closed vocabularies that exist only because a `TR-0.3.x` column needs one. They live here
// rather than in `PowerliftingCore` because nothing in the domain layer computes with them: no
// calculator reads where a bodyweight came from, which theme is on, or which *kind* of training-max
// source a configuration names. Putting them in the domain module would be the speculative symbol
// T-0.02 deleted, under a different name.
//
// **The raw values are the storage contract, wherever the type ends up living.** They are pinned by
// literal assertion here, so moving one of these to `PowerliftingCore` — or making it public when
// `TR-0.4.3`'s repository surface needs a domain spelling — is a file move rather than a migration.

/// Where a bodyweight reading came from (`TR-0.3.5`, `FR-1.8.1`, `FR-1.8.2`).
enum BodyweightSource: String, Sendable, Hashable, CaseIterable {
    /// Typed in by the user.
    case manual

    /// Read from HealthKit (`FR-1.8.2`), which is also what de-duplication runs against.
    case healthKit
}

/// Which appearance the user picked (`TR-0.3.8`, `FR-1.10.2`).
enum ThemePreference: String, Sendable, Hashable, CaseIterable {
    /// Follow the system setting. Not a colour scheme of its own.
    case system

    /// Light regardless of the system setting.
    case light

    /// Dark regardless of the system setting.
    case dark
}

/// Which of `FR-1.5.1.1`'s three sources a training-max configuration uses.
///
/// A discriminator rather than a mirror: ``PowerliftingCore/TrainingMaxSource`` carries the payload
/// in associated values, so it has no raw value to store, and the payloads are separate nullable
/// columns on `TrainingMaxConfigEntity`. Which of those columns is meaningful is decided by this.
///
/// **This is also the only column that says whether the percentage and the rounding rule took part
/// in the number** — see `TrainingMaxConfigEntity.sourceRawValue`.
enum TrainingMaxSourceKind: String, Sendable, Hashable, CaseIterable {
    /// A percentage of the best estimated one-rep maximum.
    case percentOfE1RM

    /// A percentage of the best N-rep max, where N is `sourceRepCount`.
    case percentOfRepMax

    /// The weight in `manualWeightGrams`, taken as entered (`FR-1.5.1.5`).
    case manual
}
