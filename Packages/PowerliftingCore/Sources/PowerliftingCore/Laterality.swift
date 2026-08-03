/// How an exercise's load is distributed across the body's two sides.
///
/// Stored on `ExerciseEntity` (`TR-0.3.1`) and required on every catalogue entry (`TR-0.5.1`).
///
/// > No `TR-0.2.x` defines this type — logged as gap §2 of the Phase 0 coverage matrix. T-0.11
/// > invents it beside ``Movement`` because `TR-0.3.1` names the field and nothing else does.
///
/// **It answers exactly one question: does a logged rep count cover the whole body, or one side?**
/// Ten reps of a barbell row is ten pulls; ten reps of a single-arm row is ten pulls *per arm*.
/// Nothing in Phase 0 acts on that — `SetRecord` (T-0.12) stores reps as given — but the fact has
/// to be recorded on the exercise from schema v1 or it cannot be backfilled onto history, which is
/// the argument `G-1.8` makes for `isWarmup`.
///
/// **It does not model how many implements are involved, and must not be read that way.** A
/// two-dumbbell bench press is ``bilateral``: both arms work at once and ten reps is ten reps,
/// which is the whole question this type asks. That it involves two independent loads rather than
/// one shared bar is a different axis — one this type deliberately leaves unmodelled, because
/// nothing in Phase 0 needs it and ``Equipment`` already records that the exercise uses dumbbells.
///
/// The related question of *what a logged weight means* for such an exercise — one dumbbell or the
/// pair, one limb or both — is **open, and is not decided here**. It belongs to `SetRecord`
/// (T-0.12) and affects tonnage (`FR-1.5.1`); their task files carry it.
///
/// Renaming a case is a storage migration. Reordering them is free.
///
/// **Unlike ``Movement``, ``Equipment`` and ``BarType``, this type has no unknown-value fallback
/// and an unrecognised spelling throws.** The three cases partition the one question above
/// completely: sides work together, one at a time, or in alternation, and there is no fourth
/// answer to *that* question. So an unknown value is corruption rather than a newer vocabulary,
/// and there is no meaningless case to degrade onto.
///
/// That argument is narrower than it first looks, and was narrowed on review (T-0.11): it holds
/// for the rep-counting question and **not** for laterality in some broader sense, where a fourth
/// case is easy to imagine. If this type is ever widened beyond that question, the throw has to be
/// revisited with it. The mitigation meanwhile is a decoding rule that belongs to the layer above:
/// a field that fails to decode must not cost the record that carries it (T-0.31, T-0.42).
public enum Laterality: String, Sendable, Hashable, Codable, CaseIterable {
    /// Both sides work at the same time, so a rep is one rep for the whole body — squat, bench,
    /// barbell row, **and two-dumbbell work such as a dumbbell bench press or a two-arm curl**.
    /// One shared load or two independent ones makes no difference to that; see the type's note.
    /// Also the right answer wherever the distinction does not apply, such as a plank.
    case bilateral

    /// One side works at a time and the set is performed for each — split squat, single-arm row.
    /// A rep count is therefore per side.
    case unilateral

    /// The sides alternate within a single set — alternating dumbbell curl, walking lunge. Kept
    /// separate from ``unilateral`` because the rep count covers both sides rather than one.
    case alternating
}
