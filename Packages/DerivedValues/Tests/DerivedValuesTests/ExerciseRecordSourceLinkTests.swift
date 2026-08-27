import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-1.6.2`'s links, as the state resolves them.
///
/// A suite of its own rather than a `// MARK:` in ``ExerciseRecordsStateTests``: that file had
/// reached SwiftLint's length ceiling. Same store fixtures, same rules.
@Suite("Exercise record source links")
@MainActor
struct ExerciseRecordSourceLinkTests {
    /// **`FR-1.6.2`'s link, and it is a join rather than a stored column.** The cache holds the set;
    /// the session behind it is resolved on read, so a record that moved to another workout cannot
    /// leave a link pointing at the old one.
    @Test("Each record resolves to the session its source set was performed in")
    func recordsResolveToTheirSessions() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let old = try await log.session(
            of: exerciseID, on: weeksAgo(4), sets: [working(140_000, 1)])
        let recent = try await log.session(
            of: exerciseID, on: weeksAgo(1), sets: [working(120_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        await state.load()

        // The heaviest single is four weeks back; the 5RM is last week's. Two records, two sessions.
        let single = try #require(state.repMaxes.first { $0.reps == 1 })
        let five = try #require(state.repMaxes.first { $0.reps == 5 })
        let oldSession = try #require(
            try await log.repositories.workouts.entry(id: old, includingDeleted: false)?.sessionID)
        let recentSession = try #require(
            try await log.repositories.workouts.entry(id: recent, includingDeleted: false)?
                .sessionID)
        #expect(state.sourceSessions[single.record.sourceSetID] == oldSession)
        #expect(state.sourceSessions[five.record.sourceSetID] == recentSession)
        #expect(oldSession != recentSession)
    }

    /// **A reload replaces the links with the list they belong to.** Kept across a replacement they
    /// would key on sets that are no longer records — a link on the wrong row rather than a missing
    /// one.
    @Test("Reloading the records drops links the new list does not own")
    func reloadingRecordsDropsStaleLinks() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        await state.load()
        let first = try #require(state.repMaxes.first { $0.reps == 5 }).record.sourceSetID
        #expect(state.sourceSessions[first] != nil)

        // A heavier set in a different workout takes the 5RM. The old set is no longer a record.
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(120_000, 5)])
        _ = try await recomputer.recompute(forExerciseID: exerciseID)

        // The list alone, before anything re-resolves. This is the assertion that can fail: after
        // `loadSources()` the map is replaced wholesale, so a test looking only at the end state
        // passes whether or not the replacement ever dropped the previous list's links — which is
        // exactly the window a screen draws in between the two reads.
        await state.loadRecords()
        #expect(state.sourceSessions.isEmpty)

        await state.loadSources()
        let second = try #require(state.repMaxes.first { $0.reps == 5 }).record.sourceSetID
        #expect(second != first)
        #expect(state.sourceSessions[first] == nil)
        #expect(state.sourceSessions[second] != nil)
        #expect(entryID != second)
    }
}
