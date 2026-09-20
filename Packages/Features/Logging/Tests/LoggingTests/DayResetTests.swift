import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-18.5` — taking one row's answer back.
///
/// **Every assertion here is about what was *written*, not about what the row displays.** A skip
/// and a circle write the same two things (the entry's check-off, and sets), so one command undoes
/// either; a test that asserted only `answer == .unanswered` would pass for a command that cleared
/// the mark and left five sets standing at a record.
///
/// **The deletions are soft** (`G-1.3`), so each one is checked twice — gone from the live read,
/// still there `includingDeleted: true`. A hard delete satisfies the first and is the failure this
/// pair exists for.
@MainActor
@Suite("Taking a row's answer back (FR-18.5)")
struct DayResetTests {
    // MARK: - The two answers it undoes (FR-18.5.1)

    @Test("A skipped row resets to unanswered and its circle comes back")
    func resetAfterASkip() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let rowID = try #require(day.rows.first).id
        await day.skip(rowID: rowID)
        try #require(day.rows.first?.answer == .skipped)
        let entryID = try await fixture.firstEntryID(day: 0)

        await day.reset(rowID: entryID)

        let row = try #require(day.rows.first)
        #expect(row.answer == .unanswered)
        #expect(row.hasCircle)
        let entries = try await fixture.stack.workouts.entries(
            forSessionID: try await fixture.session(day: 0).id, includingDeleted: false)
        #expect(entries.first(where: { $0.id == entryID })?.isMarkedDone == false)
    }

    @Test("A row the circle answered gives its sets up, softly, and keeps its plan")
    func resetAfterTheCircle() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        let entryID = try await fixture.firstEntryID(day: 0)
        let logged = try await fixture.stack.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        try #require(logged.count == 3)
        let planned = try await fixture.stack.workouts.plannedTargets(
            forEntryID: entryID, includingDeleted: false)
        try #require(!planned.isEmpty)

        await day.reset(rowID: entryID)

        let row = try #require(day.rows.first)
        #expect(row.answer == .unanswered)
        #expect(row.performed.isEmpty)
        #expect(row.hasCircle)
        let live = try await fixture.stack.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        #expect(live.isEmpty)
        // Soft, not hard (`G-1.3`): the rows are still there, stamped.
        let all = try await fixture.stack.workouts.sets(forEntryID: entryID, includingDeleted: true)
        #expect(all.count == 3)
        #expect(all.allSatisfy { $0.deletedAt != nil })
        // The plan is the routine's prescription, not an answer — the circle reads it next time.
        #expect(
            try await fixture.stack.workouts.plannedTargets(
                forEntryID: entryID, includingDeleted: false) == planned)
    }

    @Test("A row logged with a deviation resets like any other")
    func resetAfterADeviation() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let values = SetEntryValues(
            weight: Weight(grams: 95_000), reps: 4, rpe: nil, isWarmup: false)
        await day.log(
            rowID: try #require(day.rows.first).id,
            group: ResolvedSetGroup(values: values, sets: 3, rows: Array(repeating: values, count: 3)))
        let entryID = try await fixture.firstEntryID(day: 0)
        try #require(day.rows.first?.answer == .logged)
        try #require(day.rows.first?.wasAsPlanned == false)

        await day.reset(rowID: entryID)

        #expect(day.rows.first?.answer == .unanswered)
        #expect(
            try await fixture.stack.workouts.sets(forEntryID: entryID, includingDeleted: false)
                .isEmpty)
    }

    @Test("A row planned in two groups gives up both runs and keeps both targets")
    func resetOnATwoGroupRow() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await fixture.addLoadedGroup(day: 0, slot: 0)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        try #require(day.rows.first?.plan.count == 2)
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        let entryID = try await fixture.firstEntryID(day: 0)
        try #require(
            try await fixture.stack.workouts.sets(forEntryID: entryID, includingDeleted: false)
                .count == 5)

        await day.reset(rowID: entryID)

        #expect(day.rows.first?.answer == .unanswered)
        #expect(day.rows.first?.plan.count == 2)
        #expect(
            try await fixture.stack.workouts.sets(forEntryID: entryID, includingDeleted: false)
                .isEmpty)
    }

    @Test("An added exercise resets to an unanswered row with no circle")
    func resetOnAnAddedExercise() async throws {
        // `FR-1.2.2`: a row the plan did not name has nothing to perform "as planned", so it comes
        // back without a circle — `DayRowCircle`'s own rule, and nothing here restates it.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        try #require(await day.startIfNeeded())
        let added = UUID()
        try await fixture.stack.exercises.save(
            Exercise(
                id: added,
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                name: "Ab Wheel",
                ukrainianName: nil,
                movement: .other,
                parentExerciseID: nil,
                equipment: .bodyweight,
                laterality: .bilateral,
                barType: .noBar,
                implementCount: 1,
                isCustom: false,
                isArchived: false,
                notes: ""))
        await store.addExercise(id: added)
        let rowID = try #require(day.rows.last).id
        let values = SetEntryValues(
            weight: Weight(grams: 20_000), reps: 12, rpe: nil, isWarmup: false)
        await day.log(rowID: rowID, group: ResolvedSetGroup(values: values, sets: 1, rows: [values]))
        try #require(day.rows.last?.answer == .logged)

        await day.reset(rowID: rowID)

        let row = try #require(day.rows.last)
        #expect(row.answer == .unanswered)
        #expect(row.plan.isEmpty)
        #expect(!row.hasCircle)
    }

    // MARK: - What it leaves alone (FR-18.5.3, TR-18.2)

    @Test("A set nobody attempted is not an answer, and survives the reset")
    func aPendingSetSurvives() async throws {
        // `FR-16.4`: an import writes the work ahead of it being done. Sweeping those up would
        // delete the plan a lifter is about to perform rather than the answer they are taking back.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        let entryID = try await fixture.firstEntryID(day: 0)
        try await fixture.writePendingSet(entryID: entryID, order: 9)

        await day.reset(rowID: entryID)

        let live = try await fixture.stack.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        #expect(live.count == 1)
        #expect(live.allSatisfy { !$0.isCompleted })
    }

    @Test("A day nobody has logged into has no answer to take back and writes nothing")
    func resetOnAnUnstartedDayWritesNothing() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()

        await day.reset(rowID: try #require(day.rows.first).id)

        #expect(!day.isStarted)
        let sessions = try await fixture.stack.workouts.sessions(
            forProgramRunID: fixture.runID, week: WeekFixture.week, includingDeleted: false)
        #expect(sessions.isEmpty)
    }

    @Test("Resetting a row twice writes nothing the second time")
    func aSecondResetWritesNothing() async throws {
        // `G-2.4`: assigning a `@Model` property marks the row changed whatever the value was, so a
        // no-op save would restamp `updatedAt` — the conflict key — and outrank a real remote edit.
        // The fakes restamp on every save, which is what makes this assertable at all.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        let entryID = try await fixture.firstEntryID(day: 0)
        await day.reset(rowID: entryID)
        let entryAfterFirst = try #require(
            try await fixture.stack.workouts.entry(id: entryID, includingDeleted: false))
        let sessionAfterFirst = try await fixture.session(day: 0)

        await day.reset(rowID: entryID)

        #expect(
            try await fixture.stack.workouts.entry(id: entryID, includingDeleted: false)?.updatedAt
                == entryAfterFirst.updatedAt)
        #expect(try await fixture.session(day: 0).updatedAt == sessionAfterFirst.updatedAt)
    }

    // MARK: - The day it re-opens (FR-18.5.3)

    @Test("Resetting the last answered row re-opens the day, so NFR-1.9's wake policy re-arms")
    func theDayIsInProgressAgain() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.logRemainingAsPlanned()
        try #require(day.isDone)
        try #require(!store.isInProgress)
        let entryID = try await fixture.firstEntryID(day: 0)

        await day.reset(rowID: entryID)

        #expect(!day.isDone)
        // `isInProgress` rather than `isActive`: the second is held either way, and the first is
        // what the idle timer reads — a lifter who took an answer back is lifting again.
        #expect(store.isInProgress)
        #expect(try await fixture.session(day: 0).endedAt == nil)
        // The card reads *Continue* again, which is `FR-18.5.3` as the week sees it.
        let week = fixture.weekState()
        await week.load(openSession: nil)
        #expect(WeekFixture.days(of: week).first?.progress == .inProgress(done: 1, of: 2))
    }

    @Test("Resetting a row of a day that never ended leaves its session alone")
    func anOpenDayIsNotRewritten() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        let before = try await fixture.session(day: 0)
        try #require(before.endedAt == nil)

        await day.reset(rowID: try await fixture.firstEntryID(day: 0))

        #expect(try await fixture.session(day: 0).updatedAt == before.updatedAt)
    }

    // MARK: - The records the removed sets held (FR-18.5.4)

    @Test("A record the removed sets held is gone once the walk behind the reset has landed")
    func theRecordGoes() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        await store.settleRecordRefresh()
        let exerciseID = fixture.exerciseIDs[0][0]
        try #require(!(try await Self.records(fixture, exerciseID)).isEmpty)

        await day.reset(rowID: try await fixture.firstEntryID(day: 0))
        // The settle point, not the walk: awaiting the walk directly hangs rather than fails
        // (`T-1.93`), and nothing on screen waits for a badge.
        await store.settleRecordRefresh()

        #expect(try await Self.records(fixture, exerciseID).isEmpty)
    }

    /// The cells the cache says an exercise stands at, the unreachable marker row aside.
    ///
    /// `PersonalRecordCacheMarker` takes the `(exerciseID, 0, 0)` cell to record that an exercise
    /// was walked and found to hold nothing (`T-1.93`), so an exercise with no records is a table
    /// holding that row rather than an empty one.
    ///
    /// - Parameters:
    ///   - fixture: The week whose stack holds the cache.
    ///   - exerciseID: The exercise.
    /// - Returns: Its real cached records.
    /// - Throws: Whatever the repository throws.
    private static func records(
        _ fixture: WeekFixture, _ exerciseID: UUID
    ) async throws -> [PersonalRecordCache] {
        try await fixture.stack.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false
        ).filter { $0.repCount > 0 }
    }
}
