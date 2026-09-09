import Foundation
import PowerliftingCore

/// Which schemes `FR-1.6.5`'s feed reports on (`FR-17.3.1`, `FR-17.3.2`).
///
/// **``everyScheme`` is the un-configured value**, which is what lets the stored columns carry this
/// in their absence rather than in a discriminator of their own: no chosen list means every scheme.
/// A lifter who ticks nothing is `.chosen([])` and sees an empty feed, which is a choice they made.
///
/// **The case name is not stored** — see ``stored(reps:sets:)`` — so it is free to say what the case
/// means. It used to be `derived`, and to mean "whatever you have logged three times"; `FR-17.3.1`
/// withdrew that threshold, and what the case selects is now the whole of `FR-16.2.1`'s table.
public enum RecentRecordsSchemes: Sendable, Hashable {
    /// Every cell, narrowing nothing.
    case everyScheme

    /// Exactly these cells, whatever the history says.
    case chosen([RecordScheme])

    /// The cells chosen, or `nil` where every scheme is reported. The stored shape.
    public var chosenSchemes: [RecordScheme]? {
        guard case .chosen(let schemes) = self else { return nil }
        return schemes
    }

    /// The value two stored columns describe — chosen where both are present, every scheme
    /// otherwise.
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
        guard let reps, let sets else { return .everyScheme }
        return .chosen(zip(reps, sets).map { RecordScheme(reps: $0, sets: $1) })
    }
}
