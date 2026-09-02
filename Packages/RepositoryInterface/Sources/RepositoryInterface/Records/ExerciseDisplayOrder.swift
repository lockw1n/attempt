import Foundation

/// The order a browsable surface shows exercises in (`FR-1.14.2`).
///
/// **One home for the rule, in the module that owns the name it sorts on.** A list whose rows read
/// Cyrillic and whose order was fixed by their English names has no order its reader can use, and
/// the two are not the same permutation — `localizedStandardCompare` sorts scripts apart. Every
/// surface that draws exercise names sorts through here, in this module and in the feature modules
/// above it, so no two of them can disagree.
public enum ExerciseDisplayOrder {
    /// `exercises` in the order the names shown in `language` put them.
    ///
    /// Each name is resolved once rather than once per comparison: a screen recomputes its order on
    /// every render, which is the only way this is ever hot.
    ///
    /// The identifier breaks a tie because `G-2.5` forbids a unique constraint on the name and
    /// `Array.sorted` is not stable — two exercises reading alike would otherwise swap places
    /// between two reads of one catalogue.
    ///
    /// - Parameters:
    ///   - exercises: The rows to order.
    ///   - language: Which of the two names the caller is showing. No default: a caller that has
    ///     not decided which name it shows has not decided what its order means either.
    /// - Returns: The same exercises, ordered.
    public static func sorted(
        _ exercises: [Exercise], in language: ExerciseNameLanguage
    ) -> [Exercise] {
        exercises
            .map { (name: $0.displayName(in: language), exercise: $0) }
            .sorted { lhs, rhs in
                let byName = lhs.name.localizedStandardCompare(rhs.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return lhs.exercise.id.uuidString < rhs.exercise.id.uuidString
            }
            .map(\.exercise)
    }
}
