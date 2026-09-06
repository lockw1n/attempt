import Foundation
import PowerliftingCore
import RepositoryInterface

/// The runs `SchemeRecordCalculator` counts, out of one exercise's stored sets (`FR-16.2.1`).
///
/// **Filter-then-group fabricates adjacency, so this does neither in that order.** A record reads
/// completed working sets only, and grouping a list the warmups and failures have already been
/// dropped from joins sets a dropped one stood between: a `100 × 5`, a failed repeat of it and a
/// third would read as `100 × 5 × 2`, a run of two that never happened — and here it would be
/// *written down as a record*. A dropped set therefore **ends** the run it interrupted, and the
/// runs the filter left behind are what get grouped. `PreviousPerformance.workingRuns` is the same
/// rule on the screen that found it.
///
/// **The grain is `.loadAndReps`, explicitly and not by default.** A record is a load and a scheme;
/// a rating that drifted across four back-off sets, or a note on the last of them, does not make
/// them two schemes, and `.displayed` would split a `5 × 5` into a `5 × 3` and a `5 × 2` on an RPE
/// the record does not care about.
enum SchemeRuns {
    /// The runs `stored` holds, positioned against the collection the records are resolved through.
    ///
    /// A set the analytical type refused is dropped **and breaks its run**, on the same rule a
    /// warmup does: whatever it was, it stood between the two sets around it.
    ///
    /// - Parameters:
    ///   - stored: Every live set of one exercise, oldest first, warmups and failures included —
    ///     exactly what `WorkoutRepository.sets(forExerciseID:includingDeleted:)` returns.
    ///   - analysed: The subset this build can analyse, in the same order. Its offsets are what a
    ///     `SetRun` reports, so the caller resolves a record back through the same collection its
    ///     rep maxes are resolved through.
    /// - Returns: The runs, oldest first.
    static func runs(
        over stored: [SetEntry], offsetsInto analysed: [(SetEntry, SetRecord)]
    ) -> [SetRun] {
        let offsets = Dictionary(
            analysed.enumerated().map { ($0.element.0.id, $0.offset) },
            uniquingKeysWith: { first, _ in first })
        var runs: [[SetEntry]] = []
        var current: [SetEntry] = []
        for set in stored {
            guard offsets[set.id] != nil, !set.isWarmup, set.isCompleted else {
                if !current.isEmpty { runs.append(current) }
                current = []
                continue
            }
            current.append(set)
        }
        if !current.isEmpty { runs.append(current) }

        return runs.flatMap { SetGrouping.groups($0, at: .loadAndReps) }
            .compactMap { group in
                offsets[group.id].map {
                    SetRun(
                        weight: group.weight, reps: group.reps, count: group.count, setOffset: $0)
                }
            }
    }
}
