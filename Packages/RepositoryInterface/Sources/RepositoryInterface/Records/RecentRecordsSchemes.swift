import Foundation
import PowerliftingCore

/// Which schemes `FR-1.6.5`'s feed reports on (`FR-16.3.2`).
///
/// **Two cases and no third for "all", deliberately.** `FR-16.3.2` offers derived or chosen, and
/// "every scheme" is what ``chosen(_:)`` with the whole table says — a case meaning it would be a
/// second spelling of a selection the user can already make, and one nothing in the requirement
/// asks for.
///
/// **``derived`` is the un-configured value**, which is what lets the stored columns carry this in
/// their absence rather than in a discriminator of their own: no chosen list means derived. A lifter
/// who ticks nothing is `.chosen([])` and sees an empty feed, which is a choice they made.
public enum RecentRecordsSchemes: Sendable, Hashable {
    /// Whatever the lifter has actually trained — see ``derivedThreshold``.
    case derived

    /// Exactly these cells, whatever the history says.
    case chosen([RecordScheme])

    /// How many times a scheme has to have been performed before ``derived`` shows records at it
    /// (`FR-16.3.2`).
    ///
    /// **Three, from the requirement, and it counts *runs* rather than cells.** A `100 × 5 × 5`
    /// establishes sixty cells by dominance (`FR-16.2.2`) and is one performance of one scheme; a
    /// threshold counting cells would make `1 × 1` the most-trained scheme of every lifter alive.
    public static let derivedThreshold = 3

    /// The cells chosen, or `nil` where the schemes are derived. The stored shape.
    public var chosenSchemes: [RecordScheme]? {
        guard case .chosen(let schemes) = self else { return nil }
        return schemes
    }

    /// The value two stored columns describe — chosen where both are present, derived otherwise.
    ///
    /// **Zipped rather than indexed, so a mismatched pair truncates instead of trapping.** The two
    /// columns are written together and can only disagree in a store this app did not write, where
    /// the honest reading of an unpaired tail is that it names no cell.
    ///
    /// - Parameters:
    ///   - reps: The repetitions column.
    ///   - sets: The set-count column.
    /// - Returns: The choice those two columns carry.
    public static func stored(reps: [Int]?, sets: [Int]?) -> Self {
        guard let reps, let sets else { return .derived }
        return .chosen(zip(reps, sets).map { RecordScheme(reps: $0, sets: $1) })
    }
}
