// Three closed vocabularies that exist only because a `TR-0.3.x` column needs one, and that no
// calculator reads: nothing in the domain layer computes with where a bodyweight came from, which
// theme is on, or which *kind* of source a training-max configuration names. Putting them in
// `PowerliftingCore` would be a speculative symbol; they live here because this is the layer whose
// public surface has to spell them (`TR-0.4.3`), and `Persistence` reads them from here.
//
// **The raw values are the storage contract, wherever the type lives.** They are pinned by literal
// assertion, which is what made moving them out of `Persistence` a file move rather than a
// migration.

/// Where a bodyweight reading came from (`TR-0.3.5`, `FR-1.8.1`, `FR-1.8.2`).
public enum BodyweightSource: String, Sendable, Hashable, CaseIterable {
    /// Typed in by the user.
    case manual

    /// Read from HealthKit (`FR-1.8.2`), which is also what de-duplication runs against.
    case healthKit
}

/// Which appearance the user picked (`TR-0.3.8`, `FR-1.10.2`).
public enum ThemePreference: String, Sendable, Hashable, CaseIterable {
    /// Follow the system setting. Not a colour scheme of its own.
    case system

    /// Light regardless of the system setting.
    case light

    /// Dark regardless of the system setting.
    case dark
}

/// Which of `FR-1.5.1.1`'s three sources a training-max configuration uses.
///
/// A discriminator rather than a mirror: `PowerliftingCore`'s `TrainingMaxSource` carries the
/// payload in associated values, so it has no raw value to store, and the payloads are separate
/// nullable columns on the row. Which of those columns is meaningful is decided by this.
///
/// **This is also the only column that says whether the percentage and the rounding rule took part
/// in the number** — a manual training max keeps both as its dormant configuration (`FR-1.5.1.5`),
/// so their values disclose nothing.
public enum TrainingMaxSourceKind: String, Sendable, Hashable, CaseIterable {
    /// A percentage of the best estimated one-rep maximum.
    case percentOfE1RM

    /// A percentage of the best N-rep max, where N is the row's source rep count.
    case percentOfRepMax

    /// The weight in the row's manual-weight column, taken as entered (`FR-1.5.1.5`).
    case manual
}

/// Which exercises `FR-1.6.5`'s feed reports on (`FR-16.3.1`).
///
/// **A discriminator, not a selection.** ``chosen`` names its exercises in a column of their own and
/// ``dashboardLifts`` names none at all — it reads `FR-1.9.1`'s selection, which is the point of the
/// case existing: one place to say which lifts matter, obeyed by the tiles and by the feed.
public enum RecentRecordsScope: String, Sendable, Hashable, CaseIterable {
    /// `FR-1.9.1`'s dashboard selection, whatever it currently is. The default.
    case dashboardLifts

    /// Every exercise that holds a record.
    case everyExercise

    /// A list kept for the feed alone.
    case chosen
}
