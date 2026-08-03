/// The movement pattern an exercise trains (`TR-0.2.2`).
///
/// This is the coarse grouping the exercise library browses and filters by (`FR-1.1.1`,
/// `FR-1.1.2`) and the one field every catalogue entry must carry (`TR-0.5.1`). It is a
/// *pattern*, not an exercise: a paused competition bench, a close-grip bench and a dumbbell
/// bench press are three exercises and one `.bench`.
///
/// The raw values are the persisted spelling — they are written into `ExerciseEntity`
/// (`TR-0.3.1`) and into `exercises.json` (`TR-0.5.1`), and users' logged history is keyed to
/// exercises carrying them. **Renaming a case is a storage migration, not a refactor**, and
/// reordering the cases changes nothing, which is the whole reason the raw values are strings
/// rather than ordinals.
///
/// **Unknown values decode to ``other``** rather than throwing. See ``init(from:)`` for why, and
/// for what that costs.
public enum Movement: String, Sendable, Hashable, Codable, CaseIterable {
    /// Squat pattern — knee-dominant, bar or load supported by the torso.
    case squat

    /// Horizontal press.
    case bench

    /// Hip hinge — the deadlift pattern and its variations.
    case deadlift

    /// Vertical press.
    case overheadPress

    /// Horizontal pull.
    case row

    /// Everything the five patterns above do not describe: curls, calf raises, carries, abs.
    ///
    /// Also the landing place for a movement written by a future version of the app that this one
    /// does not recognise — see ``init(from:)``.
    case other
}

extension Movement {
    /// Decodes a movement, degrading an unrecognised spelling to ``other`` instead of throwing.
    ///
    /// `TR-0.2.2` gives this enum an ``other`` case, and the sources of an unknown value are both
    /// real: a device syncing from a newer app version (`G-2.5`), and a remote catalogue authored
    /// against a newer vocabulary (`TR-0.5.2`). Throwing would reject the whole record for the
    /// sake of one label — losing a user's logged history to protect a filter.
    ///
    /// **This loses the original string**, permanently, for that record. That is the opposite of
    /// what `NFR-2.3` requires of `Prescription` (T-0.20), and deliberately so: a movement is a
    /// label on a *catalogue entry* whose authoritative copy lives in the seed content and is
    /// restored on the next import (T-0.52), whereas a prescription is the user's own program
    /// data with no upstream copy to restore it from. The exception is a **custom** exercise
    /// (`FR-1.1.3`) created on a newer version and synced down: nothing re-supplies its movement,
    /// so the degrade is final. Accepted for Phase 0; recorded in T-0.11's notes.
    ///
    /// A non-string value still throws. That is corruption, not a newer vocabulary.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Movement(rawValue: raw) ?? .other
    }
}
