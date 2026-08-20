/// The exercise library (`FR-1.1`).
///
/// THE EXEMPLAR the other four feature modules' headers point at, which is why this type outlives
/// the scaffolding it was created to hold: `TR-1.3`'s four package edges were pinned here by four
/// aliases until a screen used them for real. `ExerciseListState` now names ``ExerciseRepository``,
/// `ExerciseListView` names ``Route`` and the token scales, and both name the domain's
/// vocabularies — so the aliases went and the imports with them. A module still carrying its four
/// is a module with no screens yet, not a module doing it differently.
public enum ExerciseLibraryModule {}
