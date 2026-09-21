import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-18.7.1`: giving a day a date before anything has been answered on it.
///
/// **A suite of its own rather than more of `DayCommandTests`**, on that suite's own rule: those
/// are the commands that answer for the rest of a day, and these are the one command that writes a
/// workout without answering anything. It is also the command that reverses what this project
/// asserted until `T-18.14` — the guard was `store.session != nil`, so the menu item was hidden
/// rather than dead, and the day a lifter backdating last Thursday is looking at offered nothing
/// (`F-13`).
@MainActor
@Suite("Dating a day nothing has been answered on")
struct DayDatingTests {
    /// `FR-18.7.1`, and the reversal of what `DayCommandTests` asserted until `T-18.14`: the command used
    /// to be guarded on `store.session != nil` and did nothing on exactly the day a lifter
    /// backdating last Thursday is looking at (`F-13`). It writes now, at `Q-18.8`'s
    /// recommendation (a) — the date is recorded on the only row that can carry one.
    @Test("Change date on an untouched day creates the workout, dated as chosen, with its plan")
    func changingTheDateOfAnUntouchedDayCreatesTheWorkout() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        #expect(!day.isStarted)
        let lastThursday = weekFixtureDay.addingTimeInterval(-86_400 * 3)

        await day.changeDate(to: lastThursday)

        let session = try #require(store.session)
        #expect(session.date == Calendar.current.startOfDay(for: lastThursday))
        #expect(session.programRunID == fixture.runID)
        #expect(session.weekNumber == WeekFixture.week)
        #expect(session.dayIndex == 0)
        #expect(session.endedAt == nil)
        // In progress, `0 of 2`: every planned row is there and none of them is an answer.
        #expect(day.rows.count == 2)
        #expect(day.rows.allSatisfy { $0.answer == .unanswered })
        #expect(day.progress.answered == 0)
        #expect(day.rows.allSatisfy { $0.performed.isEmpty })
    }

    /// **One write, counted — and the same shape as moving a day that already had one.**
    ///
    /// The row is *created* on the chosen day rather than created today and moved: a
    /// create-then-``ActiveSessionStore/changeDate(to:)`` pair is two session saves, and the second
    /// restamps `updatedAt` — `G-2.4`'s conflict key — for a date the workout never held. **The
    /// count is the instrument because the columns are not**: every store here stamps `updatedAt`
    /// from the clock on the *first* save too, so a created row and a created-then-moved row are
    /// indistinguishable by the row alone (``WorkoutWriteCounter``).
    ///
    /// **One reload of this command's own, and the numbers say which is whose.** Dating a day that
    /// already has a workout is one entry read — ``DayStore/reload()``. Dating one that has none is
    /// **two**, and the extra is not a second reload: ``ActiveSessionStore/start(on:)``'s routine
    /// copy re-reads its own list before it returns, as it does for the day's first answer. Both
    /// are pinned, so a command that reloaded twice would read three.
    @Test("Dating an untouched day is one write and one reload, not a create and a restamp")
    func datingAnUntouchedDayIsOneWrite() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let counter = WorkoutWriteCounter(wrapping: fixture.stack.workouts)
        let store = ActiveSessionStore.over(fixture.stack, workouts: counter)
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        let savesBefore = await counter.sessionSaves
        let readsBefore = await counter.entryReads

        await day.changeDate(to: weekFixtureDay.addingTimeInterval(-86_400 * 3))
        let savesAfterCreating = await counter.sessionSaves
        let readsAfterCreating = await counter.entryReads
        await day.changeDate(to: weekFixtureDay.addingTimeInterval(-86_400 * 2))
        let savesAfterMoving = await counter.sessionSaves
        let readsAfterMoving = await counter.entryReads

        #expect(savesAfterCreating == savesBefore + 1)
        #expect(savesAfterMoving == savesAfterCreating + 1)
        #expect(readsAfterMoving - readsAfterCreating == 1)
        #expect(
            readsAfterCreating - readsBefore == 2,
            """
            dating an untouched day read the entries \(readsAfterCreating - readsBefore) times — \
            one is the routine copy's own, one is this command's reload, and a third would be a \
            second reload (FR-18.7.1)
            """)
        #expect(
            try #require(store.session).date
                == Calendar.current.startOfDay(
                    for: weekFixtureDay.addingTimeInterval(-86_400 * 2)))
    }

    /// `DOD-18.9`'s third clause: what the date is *for*. A circle pressed after it lands the sets
    /// on the day that was chosen, not on today.
    @Test("A circle pressed after the date was changed lands its sets on the chosen day")
    func answersAfterDatingLandOnTheChosenDay() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        let lastThursday = weekFixtureDay.addingTimeInterval(-86_400 * 3)
        await day.changeDate(to: lastThursday)

        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)

        #expect(day.rows.first?.answer == .logged)
        let stored = try await fixture.stack.workouts.sessions(
            forProgramRunID: fixture.runID, week: WeekFixture.week, includingDeleted: false)
        #expect(stored.count == 1)
        #expect(stored.first?.date == Calendar.current.startOfDay(for: lastThursday))
    }

    /// `FR-18.7.1`'s last sentence, and it is the one that makes the write safe to offer: the day
    /// dated by mistake is one command from being upcoming again, with its plan where it was.
    @Test("Reset day on a dated but unanswered day returns it to not started with its plan")
    func resetAfterDatingReturnsTheDayToUpcoming() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.changeDate(to: weekFixtureDay.addingTimeInterval(-86_400 * 3))
        let sessionID = try #require(store.session).id

        await day.discard()

        #expect(!day.isStarted)
        #expect(day.rows.count == 2)
        #expect(day.rows.allSatisfy { $0.answer == .unanswered })
        let live = try await fixture.stack.workouts.session(
            id: sessionID, includingDeleted: false)
        #expect(live == nil)
    }

    /// **The screen-wake policy arms on a dated, unanswered day, and that is the right answer**
    /// (`NFR-1.9`). ``ActiveSessionStore/isInProgress`` is `endedAt == nil`, which a day dated from
    /// the menu satisfies — so a lifter backdating last Thursday from the sofa holds a screen that
    /// will not dim. That is what the policy is *for*: the alternative is reading "no answers yet"
    /// as "not really lifting", which is a guess about intent on the state a lifter is in for the
    /// whole of their first set. It is self-limiting either way — **Done** pops the screen and
    /// **Reset day** removes the workout.
    @Test("A dated but unanswered day is in progress, so the screen stays awake")
    func aDatedButUnansweredDayIsInProgressSoTheScreenStaysAwake() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        #expect(!store.isInProgress)

        await day.changeDate(to: weekFixtureDay.addingTimeInterval(-86_400 * 3))

        #expect(store.isInProgress)
    }

    /// The existing rule meeting the new state, confirmed rather than changed (`FR-17.8.4`): a day
    /// dated and then left is *in progress*, and a week is over only when every planned day is
    /// **done**. Skipping it or resetting it is the way past.
    @Test("A day dated and never answered blocks Start next week")
    func aDatedButUnansweredDayBlocksTheNextWeek() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.changeDate(to: weekFixtureDay.addingTimeInterval(-86_400 * 3))

        let week = fixture.weekState()
        await week.load(openSession: nil)

        #expect(!week.everyPlannedDayIsDone)
        // And the card says why: **Continue**, `0 of 2` (`FR-17.8.1`).
        let card = try #require(WeekFixture.days(of: week).first)
        #expect(card.progress == .inProgress(done: 0, of: 2))

        await day.skipRemaining()
        await week.load(openSession: nil)
        #expect(week.everyPlannedDayIsDone)
    }

    /// The state ``DayStore/hasPlan`` keeps the command out of the menu for, asserted on the store
    /// rather than on the menu: a stamp that resolves to no routine has nothing to copy, so the
    /// command writes nothing even if it is reached.
    @Test("Change date writes nothing on a day whose stamp names no routine")
    func changingTheDateOfADayWithNoPlanWritesNothing() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        // A stale stamp: `readPlan()` refuses a week the run has moved past, so there is no
        // routine and no `ProgramDay` behind this screen.
        let day = fixture.dayStore(dayIndex: 0, week: WeekFixture.week - 1)
        await day.load()
        #expect(!day.hasPlan)
        #expect(day.weekDayID == nil)

        await day.changeDate(to: weekFixtureDay)

        let sessions = try await fixture.stack.workouts.sessions(
            forProgramRunID: fixture.runID, week: WeekFixture.week - 1, includingDeleted: false)
        #expect(sessions.isEmpty)
    }

    /// **The state the menu's two parameters exist to separate** (`FR-15.2.5`). A day whose
    /// routine has been archived is still a day of the week — so **Edit plan** has somewhere to
    /// open at, and it is exactly the screen a lifter repoints the day from — while
    /// ``DayStore/startIfNeeded(on:)`` has no routine to copy, so **Change date** would be an item
    /// that writes nothing. One parameter serving both would have to pick one of those two
    /// answers, and either choice is wrong here.
    ///
    /// **`weekDayID` is therefore set before the routine is read, not after**, and that ordering is
    /// the whole of what this holds: moved one line down it would be `nil` in exactly this state
    /// and nothing else would notice.
    @Test("A day in the week whose routine has been archived has no plan and keeps its place")
    func anArchivedRoutineLeavesTheDayInTheWeek() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await fixture.stack.routines.deleteRoutine(
            id: try #require(fixture.routineIDs.first))
        let day = fixture.dayStore(dayIndex: 0)

        await day.load()

        #expect(!day.hasPlan)
        let programDays = try await fixture.stack.programs.days(
            forProgramID: fixture.programID, includingDeleted: false)
        #expect(day.weekDayID == programDays.first?.id)
        // And nothing can be started on it, which is what `hasPlan` promises.
        #expect(!(await day.startIfNeeded()))
    }

    /// The two facts `DayView` reads for the menu, on a day that has both (`FR-18.7.1`,
    /// `FR-18.7.2`). They are read off `readPlan()` and nothing else sets them.
    @Test("A day of the current week has both a plan and a place in the week")
    func aLivePlannedDayCarriesBothMenuFacts() async throws {
        let fixture = try await WeekFixture(days: 2, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 1)
        await day.load()

        #expect(day.hasPlan)
        let programDays = try await fixture.stack.programs.days(
            forProgramID: fixture.programID, includingDeleted: false)
        #expect(day.weekDayID == programDays.first { $0.order == 1 }?.id)
    }
}
