import Foundation
import RepositoryInterface

/// The order a person looks for an exercise in.
///
/// `localizedStandardCompare` puts "Ø-bar Bench" where a reader expects it, where the repositories'
/// own `id`-tiebroken byte order is for reproducibility. The tiebreak is not defensive: `FR-1.1.4`
/// renames without restriction and `G-2.5` forbids a unique constraint on the name, so two rows
/// reading "Belt Squat" is a state the store permits, and a rendering that reordered itself between
/// two of them would lose a row from a `ForEach`.
///
/// Every browsable surface in this module sorts through this, so the two cannot disagree.
enum ExerciseOrder {
    /// Whether `lhs` is shown before `rhs`, ordered by the name the screen is showing.
    ///
    /// **The compared string is the resolved one, not `name`** (`FR-1.14.2`). A list whose rows read
    /// Cyrillic and whose order was fixed by their English names is a list with no order its reader
    /// can use — and the two are not the same permutation, since `localizedStandardCompare` sorts
    /// scripts apart. There is no default for `language`: a caller that has not decided which name it
    /// is showing has not decided what its order means either.
    ///
    /// - Parameters:
    ///   - lhs: The candidate for the earlier position.
    ///   - rhs: The one it is compared against.
    ///   - language: Which of the two names the caller is showing.
    /// - Returns: `true` when `lhs` sorts first.
    static func precedes(
        _ lhs: Exercise, _ rhs: Exercise, in language: ExerciseNameLanguage
    ) -> Bool {
        let byName = lhs.displayName(in: language)
            .localizedStandardCompare(rhs.displayName(in: language))
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
