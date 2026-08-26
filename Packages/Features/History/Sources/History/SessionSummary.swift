import Foundation
import PowerliftingCore
import RepositoryInterface

/// One row of the session list: what a past workout was, in four facts (`FR-1.5.1`).
///
/// A value type built once per session and never re-read, which is the whole of this screen's
/// answer to `NFR-1.5`: scrolling reads nothing, because a row holds numbers rather than a
/// repository. The session's own records are not carried — a row that held its sets would be the
/// eager per-row load `NFR-1.5` cannot survive.
struct SessionSummary: Identifiable, Equatable, Sendable {
    /// The session this summarises. Also the row's identity and the identifier its route carries.
    let id: UUID

    /// The training day (`FR-1.2.1` backdates, so this is not when it was entered).
    let date: Date

    /// What was trained, in the order the exercises were performed, each named once.
    ///
    /// A repeated exercise — squats, then benches, then back-off squats — appears once: a summary
    /// line reading "Squat, Bench Press and Squat" says nothing the first two did not.
    let exerciseNames: [String]

    /// How many working sets were performed — completed, and not warmups (`G-1.8`).
    let setCount: Int

    /// The load moved, over the sets ``Tonnage`` can weigh.
    ///
    /// **Not every set in ``setCount`` is in here**, and the difference is a silent omission this
    /// screen does not yet explain: see ``Tonnage``.
    let tonnage: Weight

    /// The session's own note (`FR-1.2.9`), or empty.
    ///
    /// **This is where a note first becomes readable.** It is written on the workout in progress and
    /// has been stored since schema v1 with nothing showing it; the summary line is the first
    /// surface that does.
    let notes: String
}

/// The load moved in a set of logged sets — this screen's own arithmetic, and the first Phase 1
/// does outside `PowerliftingCore` (`FR-1.5.1`).
///
/// **`Σ weight × reps` over sets that are completed, are not warmups, and carry a positive load.**
/// Each of the three clauses refuses something:
///
/// - a **warmup** is excluded because `G-1.8` puts `isWarmup` on every set from schema v1 precisely
///   so analytics can leave the ramp-up out, and counting it would make two lifters' identical
///   working sets read differently;
/// - an **incomplete** set is work that did not happen (`G-1.8`'s other half);
/// - a **non-positive load** contributes nothing, because ``SetEntry/weight`` is signed on purpose —
///   assisted work is a negative added load — and summing it verbatim makes tonnage *fall* as more
///   assisted reps are done. A bodyweight set at zero likewise has nothing to weigh.
///
/// **The third clause is an omission the screen does not explain**, and it is the same silent
/// refusal the dashboard owes copy for (`FR-1.13.3`). Whatever answers it there answers it here.
///
/// **The load is the logged set's, not the implement's.** `TR-0.2.3` makes ``SetEntry/weight`` the
/// load on *one* implement, so a two-dumbbell set contributes half of what was moved and a
/// unilateral set's reps are per side. Correcting either needs the exercise's `implementCount` and
/// `laterality`; the figure here is deliberately the literal one, and the dashboard's week summary
/// must not diverge from it.
enum Tonnage {
    /// The load moved across `sets`.
    ///
    /// - Parameter sets: Every set logged against one entry, warmups and incomplete ones included —
    ///   this is what filters them, so a caller must not pre-filter and count twice.
    /// - Returns: The sum, or ``Weight/zero`` when nothing in `sets` can be weighed.
    static func of(_ sets: some Sequence<SetEntry>) -> Weight {
        sets.reduce(Weight.zero) { total, set in
            guard counts(set), set.weight > .zero, set.reps > 0 else { return total }
            return total.adding(set.weight, times: set.reps)
        }
    }

    /// Whether `set` is a working set that was performed — the population both ``of(_:)`` and
    /// ``SessionSummary/setCount`` are drawn from.
    ///
    /// - Parameter set: The set to judge.
    /// - Returns: Whether it counts as training done.
    static func counts(_ set: SetEntry) -> Bool {
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
