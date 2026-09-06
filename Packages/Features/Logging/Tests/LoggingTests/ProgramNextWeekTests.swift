import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-16.8.4`/`FR-16.8.5`: the week's days rebuilt from what was actually lifted, and nothing
/// else written.
@MainActor
@Suite("Start next week")
struct ProgramNextWeekTests {
    /// `DOD-16.1`'s second half: three days trained, three routines rebuilt, week 3 day 0 next.
    @Test("The week's days are rebuilt from the sessions and the run reads week 3, day 0")
    func theWeekIsRebuilt() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        for day in 0...2 {
            try await fixture.train(day: day, through: store, grams: 100_000 + day * 5_000)
        }
        let before = try await fixture.currentRoutineIDs()

        let state = fixture.nextUpState()
        await state.load()
        await state.startNextWeek()

        #expect(state.commandFailure == nil)
        let run = try #require(try await fixture.stack.programs.currentRun())
        #expect(run.id == fixture.runID)
        #expect(run.weekNumber == ProgramFixture.week + 1)
        #expect(run.nextDayIndex == 0)

        let after = try await fixture.currentRoutineIDs()
        #expect(after.count == 3)
        #expect(Set(after).isDisjoint(with: Set(before)))
        guard case .next(let index, let routineID, let name)? = state.nextUp?.day else {
            Issue.record("expected day 0 of the new week to be next")
            return
        }
        #expect(index == 0)
        #expect(routineID == after[0])
        // The name is carried across, so the same day is recognisable week to week.
        #expect(name == "Squat day")
    }

    /// `FR-16.8.5`: nothing writes a load the lifter did not lift or type. The rebuilt routine is
    /// `SessionAsRoutine`'s output and not a progression of the old plan — the fixture's routines
    /// prescribe 100 kg × 5 × 3 and the sessions logged something else.
    @Test("Every rebuilt target is what was lifted, not what was prescribed")
    func everyTargetIsWhatWasLifted() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        try await fixture.train(day: 0, through: store, grams: 107_500, reps: 3, sets: 2)
        try await fixture.train(day: 1, through: store, grams: 80_000, reps: 8, sets: 4)
        try await fixture.train(day: 2, through: store, grams: 140_000, reps: 1, sets: 1)

        let state = fixture.nextUpState()
        await state.load()
        await state.startNextWeek()

        let days = try await fixture.currentRoutineIDs()
        let expected = [
            PrescribedTarget(exerciseID: fixture.squat, grams: 107_500, reps: 3, sets: 2),
            PrescribedTarget(exerciseID: fixture.bench, grams: 80_000, reps: 8, sets: 4),
            PrescribedTarget(exerciseID: fixture.deadlift, grams: 140_000, reps: 1, sets: 1),
        ]
        for (index, want) in expected.enumerated() {
            #expect(try await fixture.targets(ofRoutineID: days[index]) == [want])
        }
    }

    /// Warmups and unperformed sets are `SessionAsRoutine`'s exclusions, and the rebuild inherits
    /// them rather than restating them — a rebuilt week must not prescribe a ramp.
    @Test("A warmup logged in the week is not prescribed next week")
    func warmupsAreNotPrescribed() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        let nextUp = fixture.nextUpState()
        await nextUp.load()
        let reading = try #require(nextUp.nextUp)
        guard case .next(let index, let routineID, _) = reading.day else {
            Issue.record("expected day 0 to be next")
            return
        }
        await store.start(
            on: fixture.today,
            in: ProgramSessionStamp(
                runID: reading.runID, weekNumber: reading.weekNumber, dayIndex: index),
            fromRoutineID: routineID,
            using: fixture.stack.routines)
        let entryID = try #require(store.exercises.first).entry.id
        await store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true))
        await store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))
        await store.finish()
        for day in 1...2 {
            await nextUp.load()
            await nextUp.skipDay(at: day)
        }

        await nextUp.load()
        await nextUp.startNextWeek()

        let days = try await fixture.currentRoutineIDs()
        let rebuilt = try await fixture.targets(ofRoutineID: days[0])
        #expect(rebuilt.count == 1)
        #expect(rebuilt.first?.grams == 100_000)
    }

    /// A skipped day keeps the routine it already had — and no empty routine is written for it.
    @Test("A skipped day keeps its previous routine unchanged")
    func aSkippedDayKeepsItsRoutine() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        try await fixture.train(day: 0, through: store, grams: 105_000)
        let state = fixture.nextUpState()
        await state.load()
        await state.skipDay(at: 1)
        try await fixture.train(day: 2, through: store, grams: 145_000)
        let before = try await fixture.currentRoutineIDs()

        await state.load()
        await state.startNextWeek()

        let after = try await fixture.currentRoutineIDs()
        #expect(after[1] == before[1])
        #expect(after[0] != before[0])
        #expect(after[2] != before[2])
        // Untouched, so still in the library — only a replaced routine is archived.
        #expect(
            try await fixture.stack.routines.routine(id: before[1], includingDeleted: false) != nil)
        // And unchanged: it still prescribes what the lifter authored.
        let kept = try await fixture.targets(ofRoutineID: before[1])
        #expect(kept.map(\.grams) == [100_000])
    }

    /// A day finished with nothing logged is a skipped day by another route — the empty plan must
    /// not replace a real one.
    @Test("A day finished with nothing logged keeps its previous routine")
    func anEmptySessionKeepsItsRoutine() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        try await fixture.train(day: 0, through: store, grams: nil)
        try await fixture.train(day: 1, through: store, grams: nil)
        try await fixture.train(day: 2, through: store, grams: nil)
        let before = try await fixture.currentRoutineIDs()

        let state = fixture.nextUpState()
        await state.load()
        await state.startNextWeek()

        #expect(try await fixture.currentRoutineIDs() == before)
        #expect(try await fixture.stack.programs.currentRun()?.weekNumber == ProgramFixture.week + 1)
    }

    /// `FR-15.2.5`'s archive, so the previous week is recoverable rather than lost.
    @Test("A replaced routine is archived, not deleted")
    func aReplacedRoutineIsArchived() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        for day in 0...2 { try await fixture.train(day: day, through: store, grams: 100_000) }
        let before = try await fixture.currentRoutineIDs()

        let state = fixture.nextUpState()
        await state.load()
        await state.startNextWeek()

        for routineID in before {
            #expect(
                try await fixture.stack.routines.routine(id: routineID, includingDeleted: false)
                    == nil)
            #expect(
                try await fixture.stack.routines.routine(id: routineID, includingDeleted: true)
                    != nil)
        }
    }

    /// Two days naming one routine and only one of them trained: archiving it would empty the day
    /// nobody touched, so it stays in force for that day.
    @Test("A routine another day still names is not archived")
    func aSharedRoutineSurvives() async throws {
        let fixture = try await ProgramFixture()
        // Point day 1 at day 0's routine, so one routine serves two days.
        let days = try await fixture.stack.programs.days(
            forProgramID: fixture.programID, includingDeleted: false)
        try await fixture.stack.programs.save(days[1].pointedAt(routineID: fixture.routineIDs[0]))

        let store = fixture.store()
        try await fixture.train(day: 0, through: store, grams: 102_500)
        let state = fixture.nextUpState()
        await state.load()
        await state.skipDay(at: 1)
        await state.load()
        await state.skipDay(at: 2)

        await state.load()
        await state.startNextWeek()

        let after = try await fixture.currentRoutineIDs()
        #expect(after[1] == fixture.routineIDs[0])
        #expect(
            try await fixture.stack.routines.routine(
                id: fixture.routineIDs[0], includingDeleted: false) != nil)
    }

    /// A workout still open is not what the week did — it has no `endedAt`, and the rebuild reads
    /// finished sessions only.
    @Test("A session still in progress is not what next week is built from")
    func anOpenSessionIsNotRead() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        try await fixture.train(day: 0, through: store, grams: 100_000)
        let state = fixture.nextUpState()
        await state.load()
        await state.skipDay(at: 1)
        await state.load()
        await state.skipDay(at: 2)
        // Day 0 again, still being logged when Start next week is tapped.
        await store.start(
            on: fixture.today,
            in: ProgramSessionStamp(
                runID: fixture.runID, weekNumber: ProgramFixture.week, dayIndex: 0),
            fromRoutineID: fixture.routineIDs[0],
            using: fixture.stack.routines)
        let entryID = try #require(store.exercises.first).entry.id
        await store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 200_000), reps: 1, rpe: nil, isWarmup: false))

        await state.load()
        await state.startNextWeek()

        let days = try await fixture.currentRoutineIDs()
        // The finished session's 100 kg, not the open one's 200.
        #expect(try await fixture.targets(ofRoutineID: days[0]).map(\.grams) == [100_000])
    }

    /// Two attempts at one day, on the same training date: `startedAt` is what separates them.
    ///
    /// **Both identifiers are pinned, and that is the whole of the test.** `sessions(in:)` orders
    /// by training *day* and breaks a tie on `id.uuidString` descending — so the earlier attempt is
    /// given the higher identifier here, and a rebuild reading the repository's order straight
    /// would take it every time rather than half the time.
    @Test("A day trained twice contributes the later attempt, not the higher identifier")
    func theLaterAttemptWins() async throws {
        let fixture = try await ProgramFixture()
        try await fixture.logFinishedSession(
            id: try #require(UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")),
            day: 0,
            startedAt: fixture.today,
            grams: 100_000)
        try await fixture.logFinishedSession(
            id: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001")),
            day: 0,
            startedAt: fixture.today.addingTimeInterval(3_600),
            grams: 110_000)
        let state = fixture.nextUpState()
        for day in 0...2 {
            await state.load()
            await state.skipDay(at: day)
        }

        await state.load()
        await state.startNextWeek()

        let days = try await fixture.currentRoutineIDs()
        #expect(try await fixture.targets(ofRoutineID: days[0]).map(\.grams) == [110_000])
    }

    /// The rollback, with nothing yet attached: the first re-pointing refuses, so every routine
    /// minted so far is taken back out and the week does not turn over.
    @Test("A rebuild that cannot re-point the first day leaves nothing behind")
    func aFailedRebuildLeavesNothingBehind() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        for day in 0...2 { try await fixture.train(day: day, through: store, grams: 100_000) }
        let before = try await fixture.currentRoutineIDs()
        let state = fixture.nextUpState(
            programs: RefusingProgramRepository(
                wrapped: fixture.stack.programs, refusedDayID: fixture.dayIDs[0]))
        await state.load()

        await state.startNextWeek()

        #expect(state.commandFailure == .nextWeekFailed)
        #expect(try await fixture.currentRoutineIDs() == before)
        #expect(try await fixture.stack.programs.currentRun()?.weekNumber == ProgramFixture.week)
        // Every routine in the library is one the lifter can reach from a day. Three, not six.
        #expect(try await fixture.stack.routines.routines(includingDeleted: false).count == 3)
    }

    /// The rollback's other half: a routine a day has *already* been re-pointed to is in force for
    /// that day, so deleting it would empty the day instead of undoing the write.
    @Test("A rebuild that fails part-way keeps the routines already in force")
    func aPartialRebuildKeepsWhatIsInForce() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        for day in 0...2 { try await fixture.train(day: day, through: store, grams: 100_000) }
        let before = try await fixture.currentRoutineIDs()
        let state = fixture.nextUpState(
            programs: RefusingProgramRepository(
                wrapped: fixture.stack.programs, refusedDayID: fixture.dayIDs[1]))
        await state.load()

        await state.startNextWeek()

        #expect(state.commandFailure == .nextWeekFailed)
        let after = try await fixture.currentRoutineIDs()
        // Day 0 was re-pointed before the refusal and keeps its new routine, which therefore
        // survives the rollback; days 1 and 2 are untouched.
        #expect(after[0] != before[0])
        #expect(after[1] == before[1])
        #expect(after[2] == before[2])
        #expect(
            try await fixture.stack.routines.routine(id: after[0], includingDeleted: false) != nil)
        // The week did not turn over, so the lifter can tap again.
        #expect(try await fixture.stack.programs.currentRun()?.weekNumber == ProgramFixture.week)
    }

    /// The week a session belonged to is the session's own column, so last week's sessions cannot
    /// rebuild this week's days.
    @Test("Only this week's sessions are read back")
    func onlyThisWeeksSessionsAreRead() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        try await fixture.train(day: 0, through: store, grams: 100_000)
        for day in 1...2 { try await fixture.train(day: day, through: store, grams: 100_000) }
        let state = fixture.nextUpState()
        await state.load()
        await state.startNextWeek()
        let weekThree = try await fixture.currentRoutineIDs()

        // Week 3: only day 0 is trained, at a different load.
        try await fixture.train(day: 0, through: store, grams: 120_000)
        await state.load()
        await state.skipDay(at: 1)
        await state.load()
        await state.skipDay(at: 2)
        await state.load()
        await state.startNextWeek()

        let weekFour = try await fixture.currentRoutineIDs()
        #expect(weekFour[0] != weekThree[0])
        #expect(try await fixture.targets(ofRoutineID: weekFour[0]).first?.grams == 120_000)
        // Days 1 and 2 were skipped this week, so week 3's routines carry over untouched.
        #expect(weekFour[1] == weekThree[1])
        #expect(weekFour[2] == weekThree[2])
    }
}
