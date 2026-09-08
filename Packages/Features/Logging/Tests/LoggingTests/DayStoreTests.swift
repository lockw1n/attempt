import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-17.9`'s checklist: what a day draws, and what each of its four answers writes.
@MainActor
@Suite("A day's checklist")
struct DayStoreTests {
    // MARK: - What the day reads (FR-17.9.1)

    @Test("The day carries its plan and the answers its session has")
    func theDayCarriesThePlanAndTheAnswers() async throws {
        let fixture = try await WeekFixture(days: 3, exercisesPerDay: 4)
        try await fixture.log(day: 1, done: 2)
        let day = fixture.dayStore(dayIndex: 1)

        await day.load()

        #expect(day.phase == .ready)
        #expect(day.name == "Day 2")
        #expect(day.rows.count == 4)
        // Marked done with no working set behind it is a skip — derived, never a column (`TR-17.4`).
        #expect(day.rows.map(\.answer) == [.skipped, .skipped, .unanswered, .unanswered])
        #expect(day.progress == DayProgress(day.rows))
        #expect(day.progress.answered == 2)
    }

    @Test("A day nothing has been logged into draws the plan and has no session")
    func anUntouchedDayHasNoAnswers() async throws {
        let fixture = try await WeekFixture(days: 2, exercisesPerDay: 3)
        let day = fixture.dayStore(dayIndex: 0)

        await day.load()

        #expect(day.rows.count == 3)
        #expect(!day.isStarted)
        #expect(day.progress.answered == 0)
        #expect(day.rows.allSatisfy { $0.answer == .unanswered })
    }

    @Test("A stamp naming another week draws no day, plan and answers together")
    func aStaleWeekDrawsNothing() async throws {
        // The restored-stack case. Without the check the plan would be this week's and the answers
        // last week's — one screen describing two weeks.
        let fixture = try await WeekFixture(days: 2, exercisesPerDay: 3)
        try await fixture.log(day: 0, done: 3)
        let day = fixture.dayStore(dayIndex: 0, week: WeekFixture.week + 1)

        await day.load()

        #expect(day.phase == .ready)
        #expect(day.rows.isEmpty)
        #expect(day.name.isEmpty)
    }

    @Test("A stamp naming another run draws no day either")
    func aForeignRunDrawsNothing() async throws {
        let fixture = try await WeekFixture(days: 2, exercisesPerDay: 3)
        try await fixture.log(day: 0, done: 3)
        let day = fixture.dayStore(dayIndex: 0, runID: UUID())

        await day.load()

        #expect(day.rows.isEmpty)
    }

    @Test("A day the program does not have draws nothing rather than failing")
    func aDayPastTheEndDrawsNothing() async throws {
        let fixture = try await WeekFixture(days: 2, exercisesPerDay: 3)
        let day = fixture.dayStore(dayIndex: 7)

        await day.load()

        #expect(day.phase == .ready)
        #expect(day.rows.isEmpty)
    }

    @Test("A read that failed is the day's error state, not an empty day")
    func aFailedReadIsReported() async throws {
        let fixture = try await WeekFixture(days: 2)
        let day = DayStore(
            runID: fixture.runID,
            week: WeekFixture.week,
            dayIndex: 0,
            store: fixture.activeStore(),
            programs: UnreadablePrograms(),
            routines: fixture.stack.routines,
            exercises: fixture.stack.exercises)

        await day.load()

        guard case .failed(let diagnostic) = day.phase else {
            Issue.record("expected a failed read")
            return
        }
        #expect(!diagnostic.isEmpty)
    }

    // MARK: - The first answer creates the session (FR-17.9.5)

    @Test("The first answer writes the session, its stamp and every planned exercise")
    func theFirstAnswerStartsTheDay() async throws {
        let fixture = try await WeekFixture(days: 2, exercisesPerDay: 3)
        let day = fixture.dayStore(dayIndex: 1)
        await day.load()

        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)

        let sessions = try await fixture.stack.workouts.sessions(
            forProgramRunID: fixture.runID, week: WeekFixture.week, includingDeleted: false)
        let session = try #require(sessions.first)
        #expect(session.dayIndex == 1)
        #expect(session.weekNumber == WeekFixture.week)
        #expect(session.startedAt != nil)
        let entries = try await fixture.stack.workouts.entries(
            forSessionID: session.id, includingDeleted: false)
        #expect(entries.count == 3)
        #expect(day.isStarted)
    }

    // MARK: - The circle (FR-17.9.2)

    @Test("The circle writes the planned set count at the planned load and marks the row done")
    func theCircleWritesThePlan() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()

        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)

        let row = try #require(day.rows.first)
        #expect(row.answer == .logged)
        #expect(row.wasAsPlanned)
        // The fixture's routine prescribes 100 kg × 5 × 3, and the run-length encoding says so in
        // one line rather than three.
        #expect(row.performed.count == 1)
        #expect(row.performed.first?.sets == 3)
        #expect(row.performed.first?.weight == Weight(grams: 100_000))
        #expect(row.performed.first?.reps == 5)
        let sets = try await fixture.setsOfFirstEntry(day: 0)
        #expect(sets.count == 3)
        #expect(sets.allSatisfy { $0.isCompleted })
        #expect(sets.allSatisfy { !$0.isWarmup })
    }

    @Test("The circle announces once for the whole exercise, not once per set")
    func theCircleAnnouncesOnce() async throws {
        // `NFR-17.3`: `logPlannedSet(inEntryID:)` announces to the recomputer per row and re-reads
        // the list per row — it is the precedent and not the path. An announcement is what walks an
        // exercise's sets, so the counter measures it.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let counting = SetWalkCounter(wrapped: fixture.stack.workouts)
        let store = ActiveSessionStore.over(fixture.stack, workouts: counting)
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await counting.reset()

        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)

        // Three sets written, one announcement — and the day's own end is a second, which is a
        // session-wide announcement rather than a per-set one.
        let walks = await counting.setWalks
        #expect(walks <= 2)
        let sets = try await fixture.setsOfFirstEntry(day: 0)
        #expect(sets.count == 3)
    }

    @Test("A member nobody attempted is completed rather than appended to")
    func pendingMembersAreCompleted() async throws {
        // `FR-16.4.4`, `Q-17.6`: an imported exercise can arrive holding rows with no outcome. The
        // circle is claiming those were performed, so writing new ones beside them would double
        // the work.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        await day.startIfNeeded()
        let entryID = try await fixture.firstEntryID(day: 0)
        try await fixture.writePendingSet(entryID: entryID, order: 0)

        await day.answerAsPlanned(rowID: entryID)

        let sets = try await fixture.stack.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        #expect(sets.count == 3)
        #expect(sets.allSatisfy { $0.isCompleted })
    }

    @Test("A row with no load and a row the lifter added have no circle")
    func aRowWithNoLoadHasNoCircle() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await fixture.addOpenLoadSlot(day: 0)
        let day = fixture.dayStore(dayIndex: 0)

        await day.load()

        #expect(day.rows.count == 2)
        #expect(day.rows[0].hasCircle)
        #expect(!day.rows[1].hasCircle)
        // A row with no plan at all is the one `FR-1.2.2` added, and it has nothing to perform.
        #expect(!DayRowCircle.isOffered(answer: .unanswered, plan: []))
    }

    // MARK: - Skip (FR-17.9.6)

    @Test("Skip soft-deletes the pending members and the row reads Skipped")
    func skipRemovesPendingMembers() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        await day.startIfNeeded()
        let entryID = try await fixture.firstEntryID(day: 0)
        try await fixture.writePendingSet(entryID: entryID, order: 0)

        await day.skip(rowID: entryID)

        #expect(day.rows.first?.answer == .skipped)
        let live = try await fixture.stack.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        #expect(live.isEmpty)
        let all = try await fixture.stack.workouts.sets(forEntryID: entryID, includingDeleted: true)
        #expect(all.count == 1)
        #expect(all.first?.deletedAt != nil)
    }

    @Test("Three logged and one skipped is a finished day whose card reads 3 of 4 done")
    func threeDoneAndOneSkippedFinishesTheDay() async throws {
        // `DOD-17.8`'s store half: the week's card counts answers, and a skip is one.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 4)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()

        for row in day.rows.prefix(3) {
            await day.answerAsPlanned(rowID: row.id)
        }
        await day.skip(rowID: try #require(day.rows.last).id)

        #expect(day.progress.isComplete)
        #expect(day.isDone)
        let week = fixture.weekState()
        await week.load(openSession: nil)
        let card = try #require(WeekFixture.days(of: week).first)
        #expect(card.progress == .done(on: try #require(store.session).date))
        #expect(week.answered[0]?.count == 4)
    }

    @Test("The last answer writes endedAt; the ones before it do not")
    func theLastAnswerEndsTheDay() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()

        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        #expect(store.session?.endedAt == nil)
        #expect(!day.isDone)

        await day.answerAsPlanned(rowID: try #require(day.rows.last).id)
        #expect(store.session?.endedAt != nil)
        #expect(day.isDone)
    }
}
