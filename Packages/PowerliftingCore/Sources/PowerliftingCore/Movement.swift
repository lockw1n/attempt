/// The movement pattern an exercise trains (`TR-0.2.2`).
///
/// The coarse grouping the exercise library browses and filters by (`FR-1.1.1`, `FR-1.1.2`) and
/// the one field every catalogue entry must carry (`TR-0.5.1`). It is a *pattern*, not an
/// exercise: a paused competition bench, a close-grip bench and a dumbbell bench press are three
/// exercises and one `.bench`.
///
/// The raw values are written into `ExerciseEntity` (`TR-0.3.1`) and into `exercises.json`
/// (`TR-0.5.1`), and users' logged history is keyed to exercises carrying them.
///
/// **Unknown values decode to ``other``** rather than throwing — see ``init(from:)`` for what that
/// costs.
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

    /// Everything the five patterns above do not describe: curls, calf raises, carries, abs. Also
    /// the landing place for a movement from a newer app version — see ``init(from:)``.
    case other
}

extension Movement {
    /// Decodes a movement, degrading an unrecognised spelling to ``other`` instead of throwing.
    ///
    /// `TR-0.2.2` gives this enum an ``other`` case, and both sources of an unknown value are real:
    /// a device syncing from a newer app version (`G-2.5`), and a remote catalogue authored against
    /// a newer vocabulary (`TR-0.5.2`). Throwing would reject a whole record for one label.
    ///
    /// **This loses the original string permanently for that record.** Acceptable because a
    /// movement labels a *catalogue entry* whose authoritative copy is restored on the next seed
    /// import — with one exception: a **custom** exercise (`FR-1.1.3`) created on a newer version
    /// and synced down has nothing to re-supply it, so there the degrade is final.
    ///
    /// A non-string value still throws. That is corruption, not a newer vocabulary.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Movement(rawValue: raw) ?? .other
    }
}
