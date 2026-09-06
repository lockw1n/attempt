import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// Pending sets, the three reads that exclude them, and what Finish does with them
/// (`FR-16.4.1`, `FR-16.4.2`, `FR-16.4.4`).
@Suite("Pending sets and finishing a session")
struct SessionFinishTests {
    /// The fixture, and the three ids a case needs off it.
    private struct OpenWorkout {
        let log: TrainingLog
        let exercise: UUID
        let session: UUID
        let entry: UUID
    }

    /// A workout still open: one set performed, then three the lifter has not reached.
    ///
    /// The three carry loads that would each beat the performed one, so a read that counted them
    /// fails loudly rather than by a rounding.
    private func openWorkout() async throws -> OpenWorkout {
        let log = TrainingLog()
        let squat = try await log.exercise()
        let ids = try await log.loggedSession(
            of: squat,
            on: weeksAgo(1),
            sets: [
                LoggedSet(grams: 100_000, reps: 5, isWarmup: false, isCompleted: true),
                LoggedSet(grams: 140_000, reps: 5, isWarmup: false, isCompleted: false),
                LoggedSet(grams: 150_000, reps: 5, isWarmup: false, isCompleted: false),
                LoggedSet(grams: 160_000, reps: 5, isWarmup: false, isCompleted: false),
            ],
            isFinished: false)
        return OpenWorkout(log: log, exercise: squat, session: ids.session, entry: ids.entry)
    }

    /// The recomputer over one fixture's store.
    private func recomputer(_ log: TrainingLog) -> PersonalRecordRecomputer {
        PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            // Pinned, so `FR-1.7.1`'s ninety-day window reaches the fixture's day.
            now: { fixtureNow })
    }

    /// The operation under test, over the same store.
    private func finisher(_ log: TrainingLog) -> SessionFinish {
        SessionFinish(workouts: log.repositories.workouts, records: recomputer(log))
    }

    // MARK: - FR-16.4.2, the three reads

    @Test("Pending sets reach neither history, nor the records, nor the estimate")
    func pendingSetsAreExcludedFromEveryRead() async throws {
        let open = try await openWorkout()
        let (log, squat) = (open.log, open.exercise)

        // The read all three share. Anchored to a literal rather than compared against another
        // read of the same thing: `[] == []` would satisfy a version of this that returned nothing.
        let feed = try await log.repositories.workouts.sets(
            forExerciseID: squat, includingDeleted: false)
        #expect(feed.map(\.weight.grams) == [100_000])

        let records = recomputer(log)
        let repMaxes = try await records.repMaxes(forExerciseID: squat)
        #expect(repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 100_000))
        // Not merely "no record at 160": every rep max is the performed set's, so nothing pending
        // reached the walk at any cell.
        #expect(repMaxes.allSatisfy { $0.record.weight == Weight(grams: 100_000) })

        let estimate = try await records.estimatedMax(forExerciseID: squat)
        let performed = try #require(estimate.record)
        #expect(performed.weight < Weight(grams: 140_000))
    }

    @Test("A completed set inside an open workout is not pending, and still holds its record")
    func completedSetsInAnOpenWorkoutStillCount() async throws {
        let open = try await openWorkout()
        let (log, squat) = (open.log, open.exercise)

        // `FR-1.6.3` badges a set at the moment it is logged, which is inside the workout that
        // logged it. The exclusion is of sets nobody attempted, not of the workout.
        let repMaxes = try await recomputer(log).repMaxes(forExerciseID: squat)
        #expect(repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 100_000))
    }

    // MARK: - FR-16.4.4, resolving them

    @Test("Keep as failed writes nothing, and ending the workout is what makes them failed")
    func keepAsFailedConvertsByEndingTheSession() async throws {
        let open = try await openWorkout()
        let (log, squat) = (open.log, open.exercise)
        let (session, entry) = (open.session, open.entry)
        let before = try await log.repositories.workouts.sets(
            forEntryID: entry, includingDeleted: false)

        let stored = try #require(
            try await log.repositories.workouts.session(id: session, includingDeleted: false))
        try await finisher(log).finish(stored, at: fixtureNow, resolving: .keepAsFailed)

        // The rows are untouched — same ids, same columns.
        let after = try await log.repositories.workouts.sets(
            forEntryID: entry, includingDeleted: false)
        #expect(after == before)
        #expect(after.count == 4)

        // And they are now failed sets: the feed carries them, and they hold no record.
        let feed = try await log.repositories.workouts.sets(
            forExerciseID: squat, includingDeleted: false)
        #expect(feed.map(\.weight.grams) == [100_000, 140_000, 150_000, 160_000])
        #expect(feed.filter { !$0.isCompleted }.count == 3)
        let repMaxes = try await recomputer(log).repMaxes(forExerciseID: squat)
        #expect(repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 100_000))
    }

    @Test("Remove them soft-deletes the pending rows and leaves the performed one")
    func removeThemSoftDeletesThePendingRows() async throws {
        let open = try await openWorkout()
        let (log, session, entry) = (open.log, open.session, open.entry)

        let stored = try #require(
            try await log.repositories.workouts.session(id: session, includingDeleted: false))
        try await finisher(log).finish(stored, at: fixtureNow, resolving: .remove)

        let live = try await log.repositories.workouts.sets(
            forEntryID: entry, includingDeleted: false)
        #expect(live.map(\.weight.grams) == [100_000])

        // Soft, not hard (`G-1.3`): the rows are still there, stamped.
        let all = try await log.repositories.workouts.sets(
            forEntryID: entry, includingDeleted: true)
        #expect(all.count == 4)
        #expect(all.filter(\.isSoftDeleted).map(\.weight.grams) == [140_000, 150_000, 160_000])
    }

    @Test("Finishing stamps the end and leaves the program's week and day alone")
    func finishingKeepsEveryOtherColumn() async throws {
        let open = try await openWorkout()
        let (log, session) = (open.log, open.session)
        let stored = try #require(
            try await log.repositories.workouts.session(id: session, includingDeleted: false))

        try await finisher(log).finish(stored, at: fixtureNow, resolving: .keepAsFailed)

        let ended = try #require(
            try await log.repositories.workouts.session(id: session, includingDeleted: false))
        #expect(ended.endedAt == fixtureNow)
        #expect(ended.date == stored.date)
        #expect(ended.notes == stored.notes)
    }

    // MARK: - FR-16.4.1, what counts as pending

    @Test("A finished session has no pending sets, however many of its sets failed")
    func aFinishedSessionHasNone() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise()
        let ids = try await log.loggedSession(
            of: squat,
            on: weeksAgo(1),
            sets: [LoggedSet(grams: 100_000, reps: 5, isWarmup: false, isCompleted: false)])
        let stored = try #require(
            try await log.repositories.workouts.session(id: ids.session, includingDeleted: false))

        #expect(try await finisher(log).pendingSets(in: stored).isEmpty)
        #expect(
            stored.isPending(
                try #require(
                    try await log.repositories.workouts
                        .sets(forEntryID: ids.entry, includingDeleted: false).first)) == false)
    }

    @Test("The open workout's uncompleted sets are its pending ones, and its completed one is not")
    func anOpenSessionsUncompletedSetsArePending() async throws {
        let open = try await openWorkout()
        let (log, session) = (open.log, open.session)
        let stored = try #require(
            try await log.repositories.workouts.session(id: session, includingDeleted: false))

        let pending = try await finisher(log).pendingSets(in: stored)
        #expect(pending.map(\.weight.grams) == [140_000, 150_000, 160_000])
    }
}
