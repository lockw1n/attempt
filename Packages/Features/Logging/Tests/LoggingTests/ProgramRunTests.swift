import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-16.8.2`/`FR-16.8.3`: the program's day starts a workout, and the workout carries the run,
/// the week and the day it was started from.
@MainActor
@Suite("Starting and finishing a program's day")
struct ProgramRunTests {
    @Test("A workout started from the program carries its run, week and day index")
    func theWorkoutCarriesTheRun() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        let nextUp = fixture.nextUpState()
        await nextUp.load()
        let reading = try #require(nextUp.nextUp)
        guard case .next(let index, let routineID, let name) = reading.day else {
            Issue.record("expected day 0 to be next")
            return
        }
        #expect(index == 0)
        #expect(name == "Squat day")

        #expect(
            await store.start(
                on: fixture.today,
                in: ProgramSessionStamp(
                    runID: reading.runID, weekNumber: reading.weekNumber, dayIndex: index),
                fromRoutineID: routineID,
                using: fixture.stack.routines))

        let session = try #require(store.session)
        #expect(session.programRunID == fixture.runID)
        #expect(session.weekNumber == ProgramFixture.week)
        #expect(session.dayIndex == 0)
        // FR-15.2.3's own path is still what filled it: a program day is a routine.
        #expect(store.exercises.map(\.entry.exerciseID) == [fixture.squat])
    }

    /// The three columns are written *with* the session row rather than by a second write
    /// afterwards (`NFR-1.8`): a workout force-quit before its first set still belongs to its week.
    @Test("The stamp is in the store before anything is logged into the workout")
    func theStampIsStoredAtStart() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        await store.start(
            on: fixture.today,
            in: ProgramSessionStamp(
                runID: fixture.runID, weekNumber: ProgramFixture.week, dayIndex: 0),
            fromRoutineID: fixture.routineIDs[0],
            using: fixture.stack.routines)
        let sessionID = try #require(store.session).id

        let stored = try #require(
            try await fixture.stack.workouts.session(id: sessionID, includingDeleted: false))
        #expect(stored.endedAt == nil)
        #expect(stored.programRunID == fixture.runID)
        #expect(stored.weekNumber == ProgramFixture.week)
        #expect(stored.dayIndex == 0)
    }

    @Test("Finishing the day advances the run's cursor and nothing else")
    func finishingAdvancesTheCursor() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        try await fixture.train(day: 0, through: store, grams: 100_000)

        let run = try #require(try await fixture.stack.programs.currentRun())
        #expect(run.id == fixture.runID)
        #expect(run.nextDayIndex == 1)
        #expect(run.weekNumber == ProgramFixture.week)
        #expect(run.endedAt == nil)
        #expect(store.programAdvanceFailure == nil)
    }

    /// `DOD-16.1`: all three days, each session carrying the run, week 2 and its own index, with an
    /// empty note — the structure is in the columns and no longer in the prose.
    @Test("Three days of week 2, each session stamped and each note empty")
    func wholeWeekIsStamped() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        for day in 0...2 {
            try await fixture.train(day: day, through: store, grams: 100_000 + day * 5_000)
        }

        let sessions = try await fixture.stack.workouts
            .sessions(in: Date.distantPast...Date.distantFuture, includingDeleted: false)
        #expect(sessions.count == 3)
        #expect(sessions.allSatisfy { $0.programRunID == fixture.runID })
        #expect(sessions.allSatisfy { $0.weekNumber == ProgramFixture.week })
        #expect(sessions.allSatisfy { $0.notes.isEmpty })
        #expect(Set(sessions.compactMap(\.dayIndex)) == [0, 1, 2])
        #expect(sessions.allSatisfy { $0.endedAt != nil })

        let run = try #require(try await fixture.stack.programs.currentRun())
        #expect(run.nextDayIndex == 3)

        let nextUp = fixture.nextUpState()
        await nextUp.load()
        #expect(nextUp.nextUp?.day == .weekComplete)
    }

    /// T-16.14's brief: `save` is an upsert, so a rebuild that names neither column wipes both.
    /// Annotating a program-started workout is one of the three rebuild sites.
    @Test("Saving the session note keeps the week and the day")
    func theNoteKeepsTheStamp() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        let nextUp = fixture.nextUpState()
        await nextUp.load()
        let reading = try #require(nextUp.nextUp)
        guard case .next(let index, let routineID, _) = reading.day else { return }
        await store.start(
            on: fixture.today,
            in: ProgramSessionStamp(
                runID: reading.runID, weekNumber: reading.weekNumber, dayIndex: index),
            fromRoutineID: routineID,
            using: fixture.stack.routines)

        await store.saveNote("felt heavy")

        let held = try #require(store.session)
        #expect(held.notes == "felt heavy")
        #expect(held.weekNumber == ProgramFixture.week)
        #expect(held.dayIndex == 0)
    }

    /// The second rebuild site: finishing rebuilds the record to set `endedAt`.
    @Test("Finishing keeps the week and the day on the stored row")
    func finishingKeepsTheStamp() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        let sessionID = try await fixture.train(day: 0, through: store, grams: 100_000)

        let stored = try #require(
            try await fixture.stack.workouts.session(id: sessionID, includingDeleted: false))
        #expect(stored.endedAt != nil)
        #expect(stored.weekNumber == ProgramFixture.week)
        #expect(stored.dayIndex == 0)
    }

    /// The third: `SessionNoteWriter`, which is what a *past* session's note goes through.
    @Test("Correcting a finished session's note keeps the week and the day")
    func correctingTheNoteKeepsTheStamp() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        let sessionID = try await fixture.train(day: 0, through: store, grams: 100_000)

        let writer = SessionNoteWriter(repository: fixture.stack.workouts)
        #expect(try await writer.save(id: sessionID, notes: "corrected"))

        let stored = try #require(
            try await fixture.stack.workouts.session(id: sessionID, includingDeleted: false))
        #expect(stored.notes == "corrected")
        #expect(stored.weekNumber == ProgramFixture.week)
        #expect(stored.dayIndex == 0)
    }

    @Test("A workout started outside a program advances nothing")
    func anUnplannedWorkoutAdvancesNothing() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        await store.start(on: fixture.today)
        await store.finish()

        let run = try #require(try await fixture.stack.programs.currentRun())
        #expect(run.nextDayIndex == 0)
    }

    /// The cursor only moves forward: a second session logged against a day already finished must
    /// not drag the plan back, and must not skip the day after it.
    @Test("A second session on a day already past does not move the cursor")
    func aSecondSessionDoesNotMoveTheCursor() async throws {
        let fixture = try await ProgramFixture()
        let store = fixture.store()
        try await fixture.train(day: 0, through: store, grams: 100_000)
        try await fixture.train(day: 1, through: store, grams: 100_000)

        // Day 0 again, by hand — the card would not offer it.
        await store.start(
            on: fixture.today,
            in: ProgramSessionStamp(
                runID: fixture.runID, weekNumber: ProgramFixture.week, dayIndex: 0),
            fromRoutineID: fixture.routineIDs[0],
            using: fixture.stack.routines)
        await store.finish()

        let run = try #require(try await fixture.stack.programs.currentRun())
        #expect(run.nextDayIndex == 2)
    }

    @Test("Skip day moves the cursor without writing a session")
    func skipDayMovesTheCursor() async throws {
        let fixture = try await ProgramFixture()
        let state = fixture.nextUpState()
        await state.load()

        await state.skipDay(at: 0)

        #expect(state.commandFailure == nil)
        let run = try #require(try await fixture.stack.programs.currentRun())
        #expect(run.nextDayIndex == 1)
        #expect(
            try await fixture.stack.workouts
                .sessions(in: Date.distantPast...Date.distantFuture, includingDeleted: false)
                .isEmpty)
        guard case .next(let index, _, let name)? = state.nextUp?.day else {
            Issue.record("expected day 1 to be next")
            return
        }
        #expect(index == 1)
        #expect(name == "Bench day")
    }
}
