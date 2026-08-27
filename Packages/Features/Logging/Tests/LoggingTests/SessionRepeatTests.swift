import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-1.9.2`'s repeat: a fresh workout holding a past one's exercises and nothing else.
@MainActor
@Suite("Repeating a workout")
struct SessionRepeatTests {
    @Test("The new workout holds the same exercises, in the same order")
    func thenewWorkoutHoldsTheSameExercises() async throws {
        let fixture = try await RepeatFixture()
        let store = ActiveSessionStore.over(fixture.stack)

        #expect(await store.start(on: fixture.today, repeating: fixture.sourceID))

        let session = try #require(store.session)
        #expect(session.id != fixture.sourceID)
        let entries = try await fixture.stack.workouts
            .entries(forSessionID: session.id, includingDeleted: false)
            .sorted { $0.order < $1.order }
        #expect(entries.map(\.exerciseID) == [fixture.squat, fixture.bench])
        #expect(entries.map(\.order) == [0, 1])
    }

    /// `OUT-1.1`: Phase 1 has no prescription layer, so there is nothing to pre-fill — and copying
    /// the sets would claim work that was not done.
    @Test("No sets are copied")
    func nosetsAreCopied() async throws {
        let fixture = try await RepeatFixture()
        let store = ActiveSessionStore.over(fixture.stack)

        await store.start(on: fixture.today, repeating: fixture.sourceID)

        let session = try #require(store.session)
        let entries = try await fixture.stack.workouts.entries(
            forSessionID: session.id, includingDeleted: false)
        for entry in entries {
            let sets = try await fixture.stack.workouts.sets(
                forEntryID: entry.id, includingDeleted: false)
            #expect(sets.isEmpty)
        }
    }

    /// Last week's remarks on this week's empty cards is the outcome this rules out.
    @Test("The source's per-exercise notes are left behind")
    func thesourcesNotesAreLeftBehind() async throws {
        let fixture = try await RepeatFixture()
        let store = ActiveSessionStore.over(fixture.stack)

        await store.start(on: fixture.today, repeating: fixture.sourceID)

        let session = try #require(store.session)
        let entries = try await fixture.stack.workouts.entries(
            forSessionID: session.id, includingDeleted: false)
        #expect(entries.allSatisfy { $0.notes.isEmpty })
    }

    /// ``ActiveSessionStore/start(on:)``'s invariant, not a new one: there is one active session by
    /// construction, and a repeat must not be the way around it.
    @Test("A repeat is refused while a workout is in progress")
    func arepeatIsRefusedWhileAWorkoutIsInProgress() async throws {
        let fixture = try await RepeatFixture()
        let store = ActiveSessionStore.over(fixture.stack)
        await store.start(on: fixture.today)
        let held = try #require(store.session)

        #expect(await store.start(on: fixture.today, repeating: fixture.sourceID) == false)

        #expect(store.session?.id == held.id)
        #expect(
            try await fixture.stack.workouts.entries(
                forSessionID: held.id, includingDeleted: false
            ).isEmpty)
    }

    @Test("Repeating a session that does not exist still leaves a workout in progress")
    func repeatingAMissingSessionStillStartsOne() async throws {
        let fixture = try await RepeatFixture()
        let store = ActiveSessionStore.over(fixture.stack)

        #expect(await store.start(on: fixture.today, repeating: UUID()))

        let session = try #require(store.session)
        #expect(
            try await fixture.stack.workouts.entries(
                forSessionID: session.id, includingDeleted: false
            ).isEmpty)
    }
}

/// One finished workout to repeat: two exercises, one set each, and a note on every entry.
@MainActor
private struct RepeatFixture {
    let stack = InMemoryRepositoryStack()
    let squat = UUID()
    let bench = UUID()
    let sourceID = UUID()
    let today = Date(timeIntervalSince1970: 1_700_000_000)

    init() async throws {
        for (id, name) in [(squat, "Back Squat"), (bench, "Bench Press")] {
            try await stack.exercises.save(exercise(id: id, named: name))
        }
        let past = today.addingTimeInterval(-7 * 86_400)
        try await stack.workouts.save(session(on: past))
        for (order, exerciseID) in [squat, bench].enumerated() {
            let entryID = UUID()
            try await stack.workouts.save(
                ExerciseEntry(
                    id: entryID,
                    createdAt: past,
                    updatedAt: past,
                    deletedAt: nil,
                    sessionID: sourceID,
                    exerciseID: exerciseID,
                    order: order,
                    notes: "belt on"))
            try await stack.workouts.save(set(under: entryID, on: past))
        }
    }

    /// One catalogue row.
    private func exercise(id: UUID, named name: String) -> Exercise {
        Exercise(
            id: id,
            createdAt: today,
            updatedAt: today,
            deletedAt: nil,
            name: name,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: "",
            manualE1RM: nil)
    }

    /// The finished workout being repeated, with a note of its own.
    private func session(on past: Date) -> WorkoutSession {
        WorkoutSession(
            id: sourceID,
            createdAt: past,
            updatedAt: past,
            deletedAt: nil,
            date: past,
            startedAt: past,
            endedAt: past.addingTimeInterval(3_600),
            notes: "felt strong",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil)
    }

    /// One working set under `entryID`, so the source has sets a repeat must not copy.
    private func set(under entryID: UUID, on past: Date) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: past,
            updatedAt: past,
            deletedAt: nil,
            entryID: entryID,
            order: 0,
            weight: Weight(grams: 100_000),
            reps: 5,
            rpe: nil,
            rir: nil,
            isWarmup: false,
            isCompleted: true,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: past)
    }
}
