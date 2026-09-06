import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// What `FR-1.2.10`'s strip counts as one run of sets (`FR-16.1.1`).
///
/// **A suite of its own rather than more of ``PreviousPerformanceTests``**, which had reached
/// SwiftLint's type-body ceiling: that one is about which session "last time" means and is written
/// against a repository, where these are about a value read off one session's sets.
@Suite("Previous performance runs")
struct PreviousPerformanceRunTests {
    @Test("A dropped set ends the run it stood in the middle of")
    func aFailedSetBreaksTheRunItInterrupted() {
        // The strip groups what it draws, and it draws neither warmups nor failures — so grouping
        // the filtered list would join two sets a third stood between and report `100 kg × 5 × 2`,
        // a run of two that never happened. The runs are of the day, not of the filter.
        let performance = PreviousPerformance(
            date: .distantPast,
            sets: [
                strippedSet(order: 0, reps: 5),
                strippedSet(order: 1, reps: 5, isCompleted: false),
                strippedSet(order: 2, reps: 5),
            ]
        )

        #expect(performance.workingSets.count == 2)
        #expect(performance.workingRuns.map(\.count) == [1, 1])
    }

    @Test("A run that was never interrupted is one run")
    func consecutiveWorkIsNotSplit() {
        // The negative half: without it the case above would pass on a `workingRuns` that simply
        // never joins anything.
        let performance = PreviousPerformance(
            date: .distantPast,
            sets: [
                strippedSet(order: 0, reps: 5, isWarmup: true),
                strippedSet(order: 1, reps: 5),
                strippedSet(order: 2, reps: 5),
                strippedSet(order: 3, reps: 5),
            ]
        )

        #expect(performance.workingRuns.map(\.count) == [3])
        #expect(performance.workingRuns.flatMap { $0.map(\.id) } == performance.workingSets.map(\.id))
    }

    /// One set of a previous session, with only what these two cases vary named.
    ///
    /// - Parameters:
    ///   - order: Its place among the entry's sets.
    ///   - reps: The repetitions.
    ///   - isWarmup: Whether it was a ramp, which the strip drops.
    ///   - isCompleted: Whether it was performed, which the strip drops too.
    /// - Returns: The set.
    private func strippedSet(
        order: Int,
        reps: Int,
        isWarmup: Bool = false,
        isCompleted: Bool = true
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            entryID: stripEntryID,
            order: order,
            weight: Weight(grams: 100_000),
            reps: reps,
            rpe: nil,
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

    /// The entry those sets belong to — one of them, since a run never crosses a boundary.
    private let stripEntryID = UUID()
}
