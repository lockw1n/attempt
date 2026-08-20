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
    /// Whether `lhs` is shown before `rhs`.
    ///
    /// - Parameters:
    ///   - lhs: The candidate for the earlier position.
    ///   - rhs: The one it is compared against.
    /// - Returns: `true` when `lhs` sorts first.
    static func precedes(_ lhs: Exercise, _ rhs: Exercise) -> Bool {
        let byName = lhs.name.localizedStandardCompare(rhs.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
