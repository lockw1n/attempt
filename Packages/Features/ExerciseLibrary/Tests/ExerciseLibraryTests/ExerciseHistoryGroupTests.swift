import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// What one line of `FR-1.5.2`'s history stands for (`FR-16.1.1`, `FR-16.1.2`).
///
/// **A suite of its own rather than more of ``ExerciseHistoryStateTests``**, which had reached
/// SwiftLint's file and type-body ceilings: that one is about the walk behind the section and is
/// written against a repository, where these are about a value read off one day's sets.
@Suite("Exercise history groups")
struct ExerciseHistoryGroupTests {
    @Test("A run of identical sets is one line, and every field the row draws breaks it")
    func theSectionGroupsAtTheDisplayedGrain() {
        // A history row draws the load, the reps, the rating, the warmup word and the failed mark,
        // so this section cannot group at the coarser grain a routine uses: a warmup and a working
        // set at the same load, or a set that failed between two that did not, would read as one
        // line asserting the first member's fact about all of them.
        let day = ExerciseSessionHistory(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                historySet(order: 0, isWarmup: true),
                historySet(order: 1),
                historySet(order: 2),
                historySet(order: 3, rpe: 9),
                historySet(order: 4, isCompleted: false),
            ]
        )

        // The two unvaried sets are the one run; the warmup, the drifting rating and the failure
        // each stand alone, and all five carry the same load and reps.
        #expect(day.groups.map(\.count) == [1, 2, 1, 1])
        #expect(day.groups.map(\.isWarmup) == [true, false, false, false])
    }

    @Test("An exercise performed twice in one day is two runs, not one")
    func aSecondEntryIsNotAContinuationOfTheFirst() {
        // `ExerciseSessionHistory` runs two entries together on purpose — two positions in a
        // session are one training day's work on the exercise — so the last set of the first and
        // the first set of the second are adjacent in this list and were not adjacent in the
        // workout. Merged, they would claim a run the rest of the session stood in the middle of.
        let second = UUID()
        let day = ExerciseSessionHistory(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                historySet(order: 0), historySet(order: 1),
                historySet(order: 0, entryID: second), historySet(order: 1, entryID: second),
            ]
        )

        #expect(day.groups.map(\.count) == [2, 2])
    }

    /// One logged set of a training day, with only what these two cases vary named.
    ///
    /// - Parameters:
    ///   - order: Its place among its entry's sets.
    ///   - isWarmup: Whether it was a ramp.
    ///   - isCompleted: Whether it was performed rather than failed.
    ///   - rpe: The rating, where it carried one.
    ///   - entryID: The entry it belongs to — the first unless a case is about the boundary.
    /// - Returns: The set.
    private func historySet(
        order: Int,
        isWarmup: Bool = false,
        isCompleted: Bool = true,
        rpe: Double? = 8,
        entryID: UUID? = nil
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            entryID: entryID ?? firstEntryID,
            order: order,
            weight: Weight(grams: 100_000),
            reps: 5,
            rpe: rpe,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil
        )
    }

    /// The entry those sets belong to unless a case names a second.
    private let firstEntryID = UUID()
}
