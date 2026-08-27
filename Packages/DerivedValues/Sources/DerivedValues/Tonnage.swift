import Foundation
import PowerliftingCore
import RepositoryInterface

/// The load moved in a set of logged sets (`FR-1.5.1`, `FR-1.9.5`).
///
/// **`Σ weight × reps` over sets that are completed, are not warmups, and carry a positive load.**
/// Each of the three clauses refuses something:
///
/// - a **warmup** is excluded because `G-1.8` puts `isWarmup` on every set from schema v1 precisely
///   so analytics can leave the ramp-up out, and counting it would make two lifters' identical
///   working sets read differently;
/// - an **incomplete** set is work that did not happen (`G-1.8`'s other half);
/// - a **non-positive load** contributes nothing, because ``RepositoryInterface/SetEntry/weight`` is
///   signed on purpose — assisted work is a negative added load — and summing it verbatim makes
///   tonnage *fall* as more assisted reps are done. A bodyweight set at zero likewise has nothing
///   to weigh.
///
/// **The third clause is an omission the screens do not explain**, and it is the same silent
/// refusal the dashboard owes copy for (`FR-1.13.3`). Whatever answers it on one screen answers it
/// on the other.
///
/// **The load is the logged set's, not the implement's.** `TR-0.2.3` makes
/// ``RepositoryInterface/SetEntry/weight`` the load on *one* implement, so a two-dumbbell set
/// contributes half of what was moved and a unilateral set's reps are per side. Correcting either
/// needs the exercise's `implementCount` and `laterality`; the figure here is deliberately the
/// literal one.
///
/// **It lives here rather than on either screen that reads it.** The session list (`FR-1.5.1`) and
/// the dashboard's week summary (`FR-1.9.5`) both weigh a set of sets, `TR-0.1.2` keeps one feature
/// module out of another, and two copies of these three clauses would be two answers to what a
/// lifter moved.
public enum Tonnage {
    /// The load moved across `sets`.
    ///
    /// - Parameter sets: Every set logged against one entry, warmups and incomplete ones included —
    ///   this is what filters them, so a caller must not pre-filter and count twice.
    /// - Returns: The sum, or ``PowerliftingCore/Weight/zero`` when nothing in `sets` can be
    ///   weighed.
    public static func of(_ sets: some Sequence<SetEntry>) -> Weight {
        sets.reduce(Weight.zero) { total, set in
            guard counts(set), set.weight > .zero, set.reps > 0 else { return total }
            return total.adding(set.weight, times: set.reps)
        }
    }

    /// Whether `set` is a working set that was performed — the population ``of(_:)`` is drawn from,
    /// and the one both screens count their sets over.
    ///
    /// - Parameter set: The set to judge.
    /// - Returns: Whether it counts as training done.
    public static func counts(_ set: SetEntry) -> Bool {
        set.isCompleted && !set.isWarmup
    }
}

extension Weight {
    /// This mass plus `weight` repeated `times`, skipping the term rather than trapping if it will
    /// not fit.
    ///
    /// **`Weight`'s own `*` and `+` trap on `Int` overflow, and `SetEntry.reps` is unchecked on the
    /// way in** — so a single foreign row carrying an absurd rep count would crash the screen that
    /// reads it rather than mis-report one session. A skipped term is the same silent omission the
    /// non-positive load already is, and it is owed the same explanation.
    ///
    /// - Parameters:
    ///   - weight: The load on one implement.
    ///   - times: How many times it was lifted.
    /// - Returns: The running total, unchanged if either step would overflow.
    fileprivate func adding(_ weight: Weight, times: Int) -> Weight {
        let (product, productOverflowed) = weight.grams.multipliedReportingOverflow(by: times)
        guard !productOverflowed else { return self }
        let (sum, sumOverflowed) = grams.addingReportingOverflow(product)
        guard !sumOverflowed else { return self }
        return Weight(grams: sum)
    }
}
