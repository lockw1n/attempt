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

    @Test("A plan whose backoff names no load has no circle either")
    func aBackoffWithNoLoadRemovesTheCircle() async throws {
        // The circle writes the *whole* exercise in one tap, so `isOffered` asks every group and
        // not merely the first — a plan whose backoff sets are open-load is one this command could
        // only half perform. `addOpenLoadSlot(day:)` cannot reach this: it adds a whole row.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await fixture.addOpenLoadBackoff(day: 0)
        let day = fixture.dayStore(dayIndex: 0)

        await day.load()

        let row = try #require(day.rows.first)
        #expect(row.plan.count == 2)
        // The first group names one, which is what makes this the case the rule exists for.
        #expect(row.plan.first?.weight != nil)
        #expect(row.plan.last?.weight == nil)
        #expect(!row.hasCircle)
    }

    @Test("A row that was only warmed up for reads as skipped, not as work")
    func warmupsAreNotWork() async throws {
        // `DayPerformance` leaves warmups out, so a row marked done with nothing but warmups behind
        // it has no completed *working* set and is a skip (`TR-17.4`) — a Did line that counted
        // them would report an exercise as performed for warming up to it.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.startIfNeeded()
        let entryID = try await fixture.firstEntryID(day: 0)
        try await fixture.writeWarmupSet(entryID: entryID, order: 0)
        await store.markExercise(id: entryID, isDone: true)
        await store.loadExercises()

        let row = try #require(day.rows.first { $0.id == entryID })
        #expect(row.performed.isEmpty)
        #expect(row.answer == .skipped)
    }

    @Test("An exercise added through the store appears without the screen reloading")
    func anAddedExerciseAppearsAtOnce() async throws {
        // `FR-1.2.2`'s picker is pushed above this screen and writes through the store; a pushed
        // screen's `.task` runs once, so a day holding its own copy of the list would be missing
        // the row until it was left and re-entered. Nothing here calls `load()` a second time.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.startIfNeeded()
        #expect(day.rows.count == 1)

        let catalogueID = try #require(fixture.exerciseIDs.first?.first)
        await store.addExercise(id: catalogueID)

        #expect(day.rows.count == 2)
        // It arrives with no plan, so it has no circle and Log is its only answer.
        let added = try #require(day.rows.last)
        #expect(added.plan.isEmpty)
        #expect(!added.hasCircle)
    }

    // MARK: - Log, the interim answer (FR-17.9.3)

    @Test("Log writes the set, marks the row done, and can finish the day")
    func logIsAnAnswer() async throws {
        // The only answer a row whose plan names no load can be given — the circle refuses it and
        // **Log remaining** names it rather than answering it — so it is what lets such a day reach
        // Done at all.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 0)
        try await fixture.addOpenLoadSlot(day: 0)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        let rowID = try #require(day.rows.first).id
        #expect(!day.rows[0].hasCircle)

        await day.log(
            rowID: rowID,
            group: ResolvedSetGroup(
                values: SetEntryValues(
                    weight: Weight(grams: 60_000), reps: 12, rpe: nil, isWarmup: false),
                sets: 1,
                rows: [
                    SetEntryValues(
                        weight: Weight(grams: 60_000), reps: 12, rpe: nil, isWarmup: false)
                ]))

        let row = try #require(day.rows.first)
        #expect(row.answer == .logged)
        #expect(row.performed.first?.weight == Weight(grams: 60_000))
        #expect(row.performed.first?.reps == 12)
        #expect(day.progress.isComplete)
        #expect(day.isDone)
    }

    @Test("Log writes the group it collected, marks the row done and leaves the plan alone")
    func logWritesAGroupAndNeverThePlan() async throws {
        // DOD-17.7, structurally: the fixture prescribes 100 kg × 5 × 3 and this answers it with
        // 100 kg × 4 × 3. Three actual rows, both lines on the row, and every planned row
        // field-for-field identical afterwards — `updatedAt` included, which is `G-2.4`'s conflict
        // key and the column a careless rewrite restamps.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        let rowID = try #require(day.rows.first).id

        await day.log(rowID: rowID, group: Self.group(reps: 4, sets: 3))

        let entryID = try await fixture.firstEntryID(day: 0)
        let before = try await fixture.stack.workouts.plannedTargets(
            forEntryID: entryID, includingDeleted: false)
        #expect(!before.isEmpty)
        let logged = try #require(day.rows.first)
        #expect(logged.answer == .logged)
        #expect(logged.performed.map(\.sets) == [3])
        #expect(logged.performed.first?.reps == 4)
        // Two lines: what was asked for, and what was done. `100 × 5 × 3` is not `100 × 4 × 3`.
        #expect(!logged.plan.isEmpty)
        #expect(!logged.wasAsPlanned)

        // Reopened over the answer, which is the only way to change one (`FR-17.7.5`).
        await day.log(rowID: rowID, group: Self.group(reps: 5, sets: 2))

        let rewritten = try #require(day.rows.first)
        #expect(rewritten.performed.map(\.sets) == [2])
        #expect(rewritten.performed.first?.reps == 5)
        let after = try await fixture.stack.workouts.plannedTargets(
            forEntryID: entryID, includingDeleted: false)
        #expect(after == before)
    }

    /// A group of identical rows at the fixture's own load.
    ///
    /// - Parameters:
    ///   - reps: What each set recorded.
    ///   - sets: How many.
    /// - Returns: The group.
    private static func group(reps: Int, sets: Int) -> ResolvedSetGroup {
        let values = SetEntryValues(
            weight: Weight(grams: 100_000), reps: reps, rpe: nil, isWarmup: false)
        return ResolvedSetGroup(
            values: values, sets: sets, rows: Array(repeating: values, count: sets))
    }

    @Test("The editor opens seeded from the routine on a day nothing has been logged into")
    func theEditorIsSeededFromThePlan() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()

        let rowID = try #require(day.rows.first).id
        let seed = try #require(day.seed(forRow: rowID))

        #expect(seed.weight == Weight(grams: 100_000))
        #expect(seed.reps == 5)
        // The prescribed line reports a *group* of the session's own plan, and there is no session.
        #expect(day.prescribed(forRow: rowID) == nil)
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
