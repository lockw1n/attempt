import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `OUT-17.4`'s marker: the cache can now say *computed, and there is nothing* (`G-1.5`, `NFR-1.6`).
///
/// **The shape under test is an exercise with a history and no qualifying record**, which is the one
/// `T-1.40`'s reasoning did not cover. Its argument — "an exercise with no sets has no entries to
/// fetch them through" — is true of an untrained exercise and false of one trained only for warmups,
/// only past the rep range, or only to failure: there the empty cache cost a walk of the whole
/// history on **every** read, forever, and `G-1.5`'s cache bought that exercise nothing.
///
/// **Everything here counts walks rather than timing them.** What the marker changes is how many
/// times the history is read, and a fake that records each read is the only instrument that can say
/// so — a wall-clock assertion over a fixture this size would pass whether or not the fix landed.
@Suite("Confirmed-zero marker")
struct ConfirmedZeroMarkerTests {
    /// A log, one exercise in it, and the fake that records every read of its history.
    private struct Fixture {
        let log: TrainingLog
        let exerciseID: UUID
        let counting: CountingWorkouts

        /// The recomputer over the counting fake, so every history read is recorded.
        var recomputer: PersonalRecordRecomputer {
            PersonalRecordRecomputer(
                workouts: counting, cache: log.repositories.personalRecords, now: { fixtureNow })
        }
    }

    /// A log holding one exercise trained for twelve reps — real work, past
    /// `PersonalRecords.repRange`, so it sets no record at any cell.
    private func trainedBeyondTheRepRange() async throws -> Fixture {
        let log = TrainingLog()
        let exerciseID = try await log.exercise(named: "Back Squat")
        try await log.session(of: exerciseID, on: weeksAgo(2), sets: [working(60_000, 12)])
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(65_000, 12)])
        return Fixture(
            log: log,
            exerciseID: exerciseID,
            counting: CountingWorkouts(wrapped: log.repositories.workouts))
    }

    /// The `Done when` line, and the whole point of the task: two reads, one walk.
    @Test("An exercise with history and no qualifying record is read twice and walked once")
    func aConfirmedZeroIsWalkedOnce() async throws {
        let fixture = try await trainedBeyondTheRepRange()
        let (exerciseID, counting) = (fixture.exerciseID, fixture.counting)
        let recomputer = fixture.recomputer

        let first = try await recomputer.repMaxes(forExerciseID: exerciseID)
        let walksAfterFirst = await counting.exerciseWalks
        let second = try await recomputer.repMaxes(forExerciseID: exerciseID)

        // Both reads answer "no records", which is the answer that used to cost a walk each time.
        #expect(first.isEmpty)
        #expect(second.isEmpty)
        #expect(walksAfterFirst == 1)
        #expect(await counting.exerciseWalks == 1)
    }

    /// The other read over the same rows, since the two share ``currentCache(_:)`` and a marker that
    /// only one of them recognised would leave the scheme table walking on every read.
    @Test("The scheme table hits the marker too")
    func theSchemeTableIsWalkedOnce() async throws {
        let fixture = try await trainedBeyondTheRepRange()
        let (exerciseID, counting) = (fixture.exerciseID, fixture.counting)
        let recomputer = fixture.recomputer

        _ = try await recomputer.schemeRecords(forExerciseID: exerciseID)
        let cells = try await recomputer.schemeRecords(forExerciseID: exerciseID)

        #expect(cells.isEmpty)
        #expect(await counting.exerciseWalks == 1)
    }

    /// **The marker is a row, so a reader that did not know it would answer with it.** This is the
    /// assertion that separates "the cache is empty" from "the cache says empty".
    @Test("The marker is stored, and it is one row claiming no cell")
    func theMarkerIsStored() async throws {
        let fixture = try await trainedBeyondTheRepRange()
        let (log, exerciseID) = (fixture.log, fixture.exerciseID)

        try await fixture.recomputer.recompute(forExerciseID: exerciseID)

        let stored = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        let row = try #require(stored.first)
        #expect(stored.count == 1)
        #expect(row.isConfirmedZero)
        #expect(row.scheme == RecordScheme(reps: 0, sets: 0))
        #expect(row.computationVersion == PersonalRecordCalculator.computationVersion)
    }

    /// **An untrained exercise is marked too, and that is not a widening.** It is the case
    /// `T-1.40`'s argument was actually about — the walk there is cheap — but a marker written only
    /// for the expensive case would be a second rule to keep in step, and the reads would still have
    /// to tell an empty table from a marked one.
    @Test("An exercise nobody has trained is marked as well")
    func anUntrainedExerciseIsMarked() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise(named: "Back Squat")
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let recomputer = PersonalRecordRecomputer(
            workouts: counting, cache: log.repositories.personalRecords, now: { fixtureNow })

        _ = try await recomputer.repMaxes(forExerciseID: exerciseID)
        _ = try await recomputer.repMaxes(forExerciseID: exerciseID)

        #expect(await counting.exerciseWalks == 1)
    }

    /// **A marker retires the moment the exercise holds a record**, which is
    /// `replacePersonalRecords(forExerciseID:with:)`'s reconciliation rather than a rule of its own:
    /// the marker's cell is not among the values, so it is soft-deleted like any superseded cell.
    @Test("A qualifying set retires the marker")
    func aQualifyingSetRetiresTheMarker() async throws {
        let fixture = try await trainedBeyondTheRepRange()
        let (log, exerciseID) = (fixture.log, fixture.exerciseID)
        let recomputer = fixture.recomputer
        try await recomputer.recompute(forExerciseID: exerciseID)

        try await log.session(of: exerciseID, on: weeksAgo(0), sets: [working(100_000, 5)])
        try await recomputer.recompute(forExerciseID: exerciseID)

        let stored = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(!stored.isEmpty)
        #expect(stored.allSatisfy { !$0.isConfirmedZero })
        #expect(try await recomputer.repMaxes(forExerciseID: exerciseID).map(\.reps) == [5])
    }

    /// **The marker never reaches `FR-1.6.5`'s feed**, and it is the one reader that could not be
    /// left to find out: every confirmed-zero exercise's marker names the same
    /// ``RepositoryInterface/PersonalRecordCacheMarker/unlinkedSetID``, so a feed that kept them
    /// would group them into a single event holding all of them.
    ///
    /// **Anchored on a feed that is not empty**, for the reason `theFeedReadsOnlyTheCache` is: an
    /// assertion that no marker appears in nothing proves nothing.
    @Test("Markers are not entries in the recent-records feed")
    func markersAreNotInTheFeed() async throws {
        let fixture = try await trainedBeyondTheRepRange()
        let (log, marked) = (fixture.log, fixture.exerciseID)
        let alsoMarked = try await log.exercise(named: "Front Squat")
        try await log.session(of: alsoMarked, on: weeksAgo(2), sets: [working(50_000, 15)])
        let recorded = try await log.exercise(named: "Bench Press")
        try await log.session(of: recorded, on: weeksAgo(1), sets: [working(80_000, 5)])
        let recomputer = fixture.recomputer
        for exerciseID in [marked, alsoMarked, recorded] {
            try await recomputer.recompute(forExerciseID: exerciseID)
        }

        let feed = try await recomputer.recentRecords(limit: 10)

        #expect(!feed.isEmpty)
        #expect(feed.allSatisfy { $0.exerciseID == recorded })
    }
}
