/// How an exercise's load is distributed across the body's two sides.
///
/// Stored on `ExerciseEntity` (`TR-0.3.1`) and required on every catalogue entry (`TR-0.5.1`).
///
/// **It answers exactly one question: does a logged rep count cover the whole body, or one side?**
/// Ten reps of a barbell row is ten pulls; ten reps of a single-arm row is ten pulls *per arm*.
/// Nothing in Phase 0 acts on it, but it has to exist from schema v1 or it cannot be backfilled
/// onto history — the same argument `G-1.8` makes for `isWarmup`.
///
/// **It does not model how many implements are involved, and must not be read that way.** A
/// two-dumbbell bench press is ``bilateral``: both arms work at once, which is the whole question.
///
/// **An unrecognised spelling throws**, unlike ``Movement``, ``Equipment`` and ``BarType``. The
/// three cases partition the rep-counting question completely, so an unknown value is corruption
/// rather than a newer vocabulary. That argument holds for *that* question only — widening this
/// type past it means revisiting the throw. Callers must not let the throw cost the record that
/// carries the field.
public enum Laterality: String, Sendable, Hashable, Codable, CaseIterable {
    /// Both sides work at the same time, so a rep is one rep for the whole body — squat, bench,
    /// barbell row, **and two-dumbbell work**. Also the right answer where the distinction does not
    /// apply, such as a plank.
    case bilateral

    /// One side works at a time and the set is performed for each — split squat, single-arm row.
    /// A rep count is therefore per side.
    case unilateral

    /// The sides alternate within a single set — alternating dumbbell curl, walking lunge. Separate
    /// from ``unilateral`` because the rep count covers both sides rather than one.
    case alternating
}
