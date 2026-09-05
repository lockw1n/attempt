import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import History

/// What a history row says about a workout that has not ended, and the way out it offers
/// (`FR-16.4.3`, `FR-16.4.4`).
@Suite("Session list: unfinished workouts")
struct SessionListFinishTests {
    /// The day every case here is read against.
    private let today = TrainingLog.epoch

    /// The calendar the two days are compared in.
    private let calendar = Calendar(identifier: .gregorian)

    /// One session, as the reader turns it into a row.
    private func summary(
        _ log: TrainingLog, _ session: WorkoutSession
    ) async throws -> SessionSummary {
        try await SessionSummaryReader(
            workouts: log.repositories.workouts, names: [:], today: today, calendar: calendar
        ).summary(for: session)
    }

    // MARK: - FR-16.4.3

    @Test("A finished workout keeps its numbers; an open one says what it is instead")
    func anOpenWorkoutNamesItsState() async throws {
        let log = TrainingLog()
        let finished = try await log.session(daysAgo: 2)
        let inProgress = try await log.session(daysAgo: 0, isFinished: false)
        let planned = try await log.session(daysAgo: -7, isFinished: false)

        #expect(try await summary(log, finished).lifecycle == .finished)
        #expect(try await summary(log, inProgress).lifecycle == .inProgress)
        #expect(try await summary(log, planned).lifecycle == .planned)
    }

    @Test("A workout dated today is in progress all day, not planned until the clock passes it")
    func todayIsInProgress() async throws {
        // `date` is the training day rather than an instant, so a session stamped at midnight is
        // not "planned" for the rest of the morning.
        let log = TrainingLog()
        let midnight = try await log.session(daysAgo: 0, isFinished: false)

        #expect(midnight.lifecycle(on: today, calendar: calendar) == .inProgress)
        #expect(
            midnight.lifecycle(on: today.addingTimeInterval(-3600), calendar: calendar)
                == .inProgress)
    }

    // MARK: - FR-16.4.4

    @Test("Only a workout left open past its own day offers a way to end it")
    func onlyAStaleWorkoutOffersFinish() async throws {
        let log = TrainingLog()
        let yesterday = try await log.session(daysAgo: 1, isFinished: false)
        let openToday = try await log.session(daysAgo: 0, isFinished: false)
        let planned = try await log.session(daysAgo: -7, isFinished: false)
        let finished = try await log.session(daysAgo: 2)

        // Today's is finished where it is being logged; a day ahead has nothing to end.
        #expect(try await summary(log, yesterday).canFinish)
        #expect(try await summary(log, openToday).canFinish == false)
        #expect(try await summary(log, planned).canFinish == false)
        #expect(try await summary(log, finished).canFinish == false)
    }

    @Test("Finishing a workout with pending sets asks first, and ends it on the answer")
    func finishingAsksAboutPendingSets() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let stale = try await log.session(daysAgo: 1, isFinished: false)
        let entry = try await log.entry(squat, in: stale, order: 0)
        _ = try await log.set(in: entry, kilograms: 100, reps: 5, isCompleted: true)
        _ = try await log.set(in: entry, order: 1, kilograms: 110, reps: 5, isCompleted: false)

        let state = log.listState()
        await state.load()
        await state.beginFinish(sessionID: stale.id)

        // Asked, not done: the row is still open behind the question.
        let prompt = try #require(state.pendingPrompt)
        #expect(prompt.sessionID == stale.id)
        #expect(prompt.count == 1)
        let held = try #require(
            try await log.repositories.workouts.session(id: stale.id, includingDeleted: false))
        #expect(held.endedAt == nil)

        await state.finish(sessionID: stale.id, resolving: .keepAsFailed)

        #expect(state.pendingPrompt == nil)
        let ended = try #require(
            try await log.repositories.workouts.session(id: stale.id, includingDeleted: false))
        #expect(ended.endedAt != nil)
        // And the row it left behind no longer offers the command.
        #expect(state.summaries.first { $0.id == stale.id }?.canFinish == false)
    }

    @Test("Remove them soft-deletes the pending rows and keeps what was performed")
    func removeThemKeepsWhatWasPerformed() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let stale = try await log.session(daysAgo: 1, isFinished: false)
        let entry = try await log.entry(squat, in: stale, order: 0)
        _ = try await log.set(in: entry, kilograms: 100, reps: 5, isCompleted: true)
        _ = try await log.set(in: entry, order: 1, kilograms: 110, reps: 5, isCompleted: false)

        let state = log.listState()
        await state.load()
        await state.finish(sessionID: stale.id, resolving: .remove)

        let live = try await log.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(live.map(\.weight.grams) == [100_000])
        let all = try await log.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: true)
        #expect(all.count == 2)
    }

    @Test("A workout with nothing pending is ended by the first tap")
    func nothingPendingEndsStraightAway() async throws {
        let log = TrainingLog()
        let stale = try await log.session(daysAgo: 1, isFinished: false)

        let state = log.listState()
        await state.load()
        await state.beginFinish(sessionID: stale.id)

        #expect(state.pendingPrompt == nil)
        let ended = try #require(
            try await log.repositories.workouts.session(id: stale.id, includingDeleted: false))
        #expect(ended.endedAt != nil)
    }
}
