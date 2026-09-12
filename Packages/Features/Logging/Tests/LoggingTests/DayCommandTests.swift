import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-17.9.9`'s two whole-day commands, `FR-17.9.7`'s menu, and `DOD-17.6`'s walk.
///
/// A second suite rather than a longer one, on the source side's rule: the first is what a day
/// reads and what one answer writes, and these are the commands that answer for the rest of it.
@MainActor
@Suite("A day's whole-day commands")
struct DayCommandTests {
    // MARK: - The whole-day commands (FR-17.9.9)

    @Test("Log remaining writes the loaded rows, leaves the open-load one and names it")
    func logRemainingAnswersWhatItCan() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 3)
        try await fixture.addOpenLoadSlot(day: 0)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)

        await day.logRemainingAsPlanned()

        #expect(day.rows.filter { $0.answer == .logged }.count == 3)
        #expect(day.rows.last?.answer == .unanswered)
        #expect(day.unanswerable.count == 1)
        #expect(day.unanswerable.first?.id == day.rows.last?.id)
        #expect(!day.progress.isComplete)
        #expect(!day.isDone)
    }

    @Test("Skip remaining on a day never started creates the session and finishes it")
    func skipRemainingStartsAndFinishes() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 3)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()

        await day.skipRemaining()

        #expect(day.rows.allSatisfy { $0.answer == .skipped })
        #expect(day.isDone)
        let week = fixture.weekState()
        await week.load(openSession: nil)
        let card = try #require(WeekFixture.days(of: week).first)
        #expect(card.progress == .done(on: try #require(store.session).date))
        // Every row answered, and none of them performed: `0 of 3` on the day, **Done** on the week.
        #expect(DayProgress(day.rows).answered == 3)
        #expect(day.rows.allSatisfy { $0.performed.isEmpty })
    }

    @Test("Neither whole-day command is offered once every row is answered")
    func theFootCommandsRetire() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        #expect(day.progress.offersWholeDayCommands)

        await day.skipRemaining()

        #expect(!day.progress.offersWholeDayCommands)
        // An empty day offers neither either: there is nothing to answer for.
        #expect(!DayProgress([]).offersWholeDayCommands)
    }

    @Test("Log remaining writes no workout on a day where nothing can be answered")
    func logRemainingStartsNothingItCannotAnswer() async throws {
        // `FR-17.9.5` creates the session at the *first answer*. A day whose every row names no
        // load has no answer to give, and a workout written here would hold nothing while the
        // week's card read it as in progress.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 0)
        try await fixture.addOpenLoadSlot(day: 0)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        #expect(day.rows.count == 1)

        await day.logRemainingAsPlanned()

        #expect(!day.isStarted)
        // The result is still owed: the lifter asked, and is told which row went unanswered.
        #expect(day.unanswerable.count == 1)
        let sessions = try await fixture.stack.workouts.sessions(
            forProgramRunID: fixture.runID, week: WeekFixture.week, includingDeleted: false)
        #expect(sessions.isEmpty)
    }

    @Test("Skip remaining writes no workout on a day whose routine has no exercises")
    func skipRemainingStartsNothingOnAnEmptyDay() async throws {
        // Reachable from the week card's own menu (`FR-17.8.8`), which is offered on every card
        // that is not done. A session with no entries could never be ended — `finishIfComplete()`
        // refuses an empty one — so the card would read in progress for the rest of the week.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 0)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        #expect(day.rows.isEmpty)

        await day.skipRemaining()

        #expect(!day.isStarted)
        let sessions = try await fixture.stack.workouts.sessions(
            forProgramRunID: fixture.runID, week: WeekFixture.week, includingDeleted: false)
        #expect(sessions.isEmpty)
        let week = fixture.weekState()
        await week.load(openSession: nil)
        #expect(WeekFixture.days(of: week).first?.progress == .notStarted)
    }

    // MARK: - Which workout a screen is asking for (FR-17.9.5, OUT-17.3)

    @Test("A day's session and a free workout are two, and each screen gets its own")
    func aDayAndAFreeWorkoutAreTwoSessions() async throws {
        // The store's read was "the one open session". A lifter can have a day part-answered and a
        // workout no program planned open at the same time; a read that took the first unfinished
        // row would hand one screen the other's workout.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let free = try await fixture.writeFreeWorkout()
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)

        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)

        let dayed = try #require(store.session)
        #expect(dayed.id != free.id)
        #expect(dayed.programRunID == fixture.runID)
        #expect(dayed.endedAt == nil, "the day is not finished, so both are open at once")

        // The root asks for the free workout and gets that one back, not the day's.
        await store.resume()
        #expect(store.session?.id == free.id)

        // And the day asks again and gets its own, which the free workout being newer must not
        // decide: `sessions(in:)` is ordered newest first.
        await store.open(.day(runID: fixture.runID, week: WeekFixture.week, dayIndex: 0))
        #expect(store.session?.id == dayed.id)
    }

    @Test("Resume keeps a free workout it already holds and drops a day's")
    func resumeReleasesADaysSession() async throws {
        // `FR-17.8.8`'s card command re-points the one store at a day and `resume()` is what puts
        // it back — so resume's own guard has to keep a free workout and let go of a day.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let free = try await fixture.writeFreeWorkout()
        let store = fixture.activeStore()
        await store.resume()
        #expect(store.session?.id == free.id)

        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        #expect(store.session?.programRunID != nil)

        await store.resume()

        #expect(store.session?.id == free.id)
    }

    // MARK: - The overflow menu (FR-17.9.7)

    @Test("Change date rewrites the training day and nothing else")
    func changingTheDateRewritesOnlyTheDate() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.startIfNeeded()
        let before = try #require(store.session)

        await day.changeDate(to: weekFixtureDay.addingTimeInterval(-86_400 * 3))

        let after = try #require(store.session)
        #expect(after.date != before.date)
        #expect(after.id == before.id)
        #expect(after.programRunID == before.programRunID)
        #expect(after.weekNumber == before.weekNumber)
        #expect(after.dayIndex == before.dayIndex)
        #expect(after.startedAt == before.startedAt)
        #expect(after.endedAt == before.endedAt)
    }

    @Test("Change date normalises to the start of the training day")
    func changingTheDateNormalisesIt() async throws {
        // `start(on:)`'s rule: the day, not the moment the picker was closed — a session dated to
        // an afternoon sorts and groups against midnight-dated ones everywhere else.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.startIfNeeded()
        let afternoon = weekFixtureDay.addingTimeInterval(-86_400 * 3 + 55_000)

        await day.changeDate(to: afternoon)

        let stored = try #require(store.session).date
        #expect(stored == Calendar.current.startOfDay(for: afternoon))
        #expect(stored != afternoon)
        #expect(day.date == stored)
    }

    @Test("Answering a row that is already done does not restamp it")
    func answeringATwiceDoneRowLeavesItAlone() async throws {
        // Assigning a `@Model` property marks the row changed whatever the value was, and
        // `updatedAt` is `G-2.4`'s conflict key — so a no-op local write would outrank a real
        // remote edit of the same entry.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        let rowID = try #require(day.rows.first).id
        await day.answerAsPlanned(rowID: rowID)
        let entryID = try await fixture.firstEntryID(day: 0)
        let sessionID = try await fixture.session(day: 0).id
        let stored = try await fixture.stack.workouts.entries(
            forSessionID: sessionID, includingDeleted: false)
        let before = try #require(stored.first { $0.id == entryID })

        await day.skip(rowID: entryID)

        let reread = try await fixture.stack.workouts.entries(
            forSessionID: sessionID, includingDeleted: false)
        let after = try #require(reread.first { $0.id == entryID })
        #expect(after.isMarkedDone)
        #expect(after.updatedAt == before.updatedAt)
    }

    @Test("Change date does nothing on a day that has not been started")
    func changingTheDateOfAnUnstartedDayWritesNothing() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()

        await day.changeDate(to: weekFixtureDay)

        let sessions = try await fixture.stack.workouts.sessions(
            forProgramRunID: fixture.runID, week: WeekFixture.week, includingDeleted: false)
        #expect(sessions.isEmpty)
    }

    @Test("Discard soft-deletes the day's workout and puts the day back to unstarted")
    func discardRemovesTheWorkout() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        let sessionID = try #require(store.session).id

        await day.discard()

        #expect(!day.isStarted)
        #expect(day.rows.count == 2)
        #expect(day.rows.allSatisfy { $0.answer == .unanswered })
        let live = try await fixture.stack.workouts.session(
            id: sessionID, includingDeleted: false)
        #expect(live == nil)
    }

    // MARK: - NFR-1.9

    @Test("A day that has ended is still held, and is no longer a workout in progress")
    func aFinishedDayIsHeldButNotInProgress() async throws {
        // `NFR-1.9`, and the defect the phone measured: `endDay()` keeps the row on purpose so the
        // checklist can draw it, and the idle timer read that held row as a workout in progress —
        // so a phone left alone after the last answer never locked. The two readings are asserted
        // together here, because it is their disagreement that is the fix.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)
        #expect(store.isInProgress)
        #expect(ScreenWakePreference().keepsScreenAwake(duringSession: store.isInProgress))

        await day.answerAsPlanned(rowID: try #require(day.rows.last).id)

        #expect(day.isDone)
        // Held, so `FR-17.7.5`'s read-only day still draws and **Log** still edits it.
        #expect(store.isActive)
        #expect(store.session != nil)
        // And released, so the screen dims.
        #expect(!store.isInProgress)
        #expect(!ScreenWakePreference().keepsScreenAwake(duringSession: store.isInProgress))
    }

    @Test("A day nobody has answered holds no workout, so it holds no screen either")
    func anUnansweredDayIsNotInProgress() async throws {
        // The other end of `NFR-1.9`'s wording, decided rather than inherited: a day that is open
        // and unanswered has no session row at all (`FR-17.9.5`), the lifter is reading a plan, and
        // the screen may dim. The first answer takes the hold back — asserted above.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)

        await day.load()

        #expect(!day.isStarted)
        #expect(!store.isActive)
        #expect(!store.isInProgress)
    }

    // MARK: - DOD-17.6's walk

    @Test("Three days of a week, one tap per exercise, every day done")
    func aWholeWeekIsOneTapPerExercise() async throws {
        // `DOD-17.6`'s walk, as the `DayStore` walk the criterion's "UI test" is met by — the app
        // target has no test target (`T-1.81`). Nothing but `answerAsPlanned` is called.
        let fixture = try await WeekFixture(days: 3, exercisesPerDay: 4)
        let store = fixture.activeStore()

        for index in [1, 0, 2] {
            let day = fixture.dayStore(dayIndex: index, store: store)
            await day.load()
            for row in day.rows {
                await day.answerAsPlanned(rowID: row.id)
            }
            #expect(day.isDone, "day \(index) did not finish")
            #expect(day.progress.answered == 4)
        }

        // Days in any order (`D-17.10`), and every card reads Done afterwards.
        let week = fixture.weekState()
        await week.load(openSession: nil)
        for card in WeekFixture.days(of: week) {
            guard case .done = card.progress else {
                Issue.record("day \(card.dayIndex) is not done")
                continue
            }
        }
    }

    // MARK: - FR-17.4.3

    @Test("A day whose every row is skipped is not a workout on the week's tile")
    func aWhollySkippedDayIsNoWorkout() async throws {
        // `FR-17.4.3`, orphaned until now: the tile counts a day as trained when any of its sets
        // satisfies `Tonnage.counts`, which is what `WeekSummaryState.weigh` asks — asserted here
        // over that predicate rather than over the Dashboard's state, `TR-1.3` forbidding this
        // package from importing it.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 3)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()

        await day.skipRemaining()

        #expect(day.rows.allSatisfy { $0.performed.isEmpty })
        let session = try await fixture.session(day: 0)
        let entries = try await fixture.stack.workouts.entries(
            forSessionID: session.id, includingDeleted: false)
        var counted: [SetEntry] = []
        for entry in entries {
            counted += try await fixture.stack.workouts.sets(
                forEntryID: entry.id, includingDeleted: false
            ).filter(Tonnage.counts)
        }
        #expect(counted.isEmpty)
        // And the same day answered instead of skipped *is* a workout, so the assertion above is
        // about the skip rather than about the fixture.
        let trained = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let other = trained.dayStore(dayIndex: 0)
        await other.load()
        await other.answerAsPlanned(rowID: try #require(other.rows.first).id)
        let sets = try await trained.setsOfFirstEntry(day: 0)
        #expect(sets.contains(where: Tonnage.counts))
    }

    // MARK: - The record mark (FR-1.6.3)

    @Test("A day answered as planned carries the record its work set")
    func theRowCarriesItsRecord() async throws {
        // The badge's data half. A finished session's sets count towards records where an open
        // one's do not, so this is also an assertion about the order in `reload()`: the day is
        // ended before the list — and therefore the marks — are re-read.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()

        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)

        #expect(day.isDone)
        // The answer announces without waiting (`NFR-1.2`), so the badge is what the refresh chain
        // publishes rather than what the tap returned — and the assertion has to wait for it or it
        // is asserting on whichever continuation ran first.
        await day.store.settleRecordRefresh()
        #expect(!(try #require(day.rows.first).records.isEmpty))
    }

    @Test("A skipped row carries no record, having done no work")
    func aSkippedRowCarriesNoRecord() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()

        await day.skipRemaining()

        await day.store.settleRecordRefresh()
        #expect(try #require(day.rows.first).records.isEmpty)
    }
}

/// Which identity a day's rows carry, and what that decides (`FR-17.9.4`, `FR-17.7.5`).
///
/// **Its own suite because the fact is the store's rather than any one command's**: every screen
/// that holds a row id across the first answer of a day is holding one the list stops using, and
/// the Log sheet's save is the first to have had to notice.
@MainActor
@Suite("A day's row identities")
struct DayRowIdentityTests {
    @Test("The start renumbers the rows, so answered-ness is asked about the entry")
    func answerednessIsAskedAboutTheEntry() async throws {
        // The two facts the Log sheet's save rests on, and the pair that made it read every first
        // answer of a day as a correction. (1) Creating the session renumbers `rows` from the
        // routine's slots onto the entries the copy wrote, so the id the sheet was opened on is
        // one the list no longer holds — `entryID(forRow:)` is the translation. (2) A row the day
        // does not hold is *not* answered: written as a comparison against the optional that
        // misses, `nil != .unanswered` is true, and appending is the only one of the two branches
        // that cannot soft-delete a set the lifter has.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        let slotID = try #require(day.rows.first).id

        #expect(!day.isAnswered(rowID: slotID))
        #expect(await day.startIfNeeded())
        let entryID = try #require(day.rows.first).id
        #expect(entryID != slotID, "the start is expected to renumber the rows")
        #expect(!day.isAnswered(rowID: slotID))
        #expect(!day.isAnswered(rowID: entryID))

        await day.answerAsPlanned(rowID: entryID)
        #expect(day.isAnswered(rowID: entryID))
        #expect(!day.isAnswered(rowID: slotID))
    }
}
