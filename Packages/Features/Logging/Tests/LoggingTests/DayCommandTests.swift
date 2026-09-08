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
        #expect(!(try #require(day.rows.first).records.isEmpty))
    }

    @Test("A skipped row carries no record, having done no work")
    func aSkippedRowCarriesNoRecord() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()

        await day.skipRemaining()

        #expect(try #require(day.rows.first).records.isEmpty)
    }
}
