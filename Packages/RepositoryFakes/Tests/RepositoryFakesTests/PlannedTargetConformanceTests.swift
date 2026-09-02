import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// The targets a session's exercises were planned with (`TR-15.3`), against both implementations.
///
/// A suite of its own beside `RoutineConformanceTests`, because these rows are the *session's*
/// rather than the routine's — the snapshot outliving its template is the whole point of the type,
/// and the test that proves it belongs where a session is what gets deleted.
@Suite("Conformance — planned targets")
struct PlannedTargetConformanceTests {
    @Test(
        "An entry with two planned groups round-trips, order and boundaries intact",
        arguments: Subject.all
    )
    func plannedGroupsRoundTrip(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let entry = try await seedEntry(in: repositories)

        let topSet = plannedTargetGroupRecord(
            exerciseEntryID: entry.id, order: 0, grams: 90_000, reps: 4, sets: 1)
        let backoff = plannedTargetGroupRecord(
            exerciseEntryID: entry.id, order: 1, grams: 80_000, reps: 5, sets: 3)
        // Saved out of order, so a read that trusted insertion order would still fail.
        try await repositories.plannedTargets.save(backoff)
        try await repositories.plannedTargets.save(topSet)

        let read = try await repositories.plannedTargets.plannedTargets(
            forEntryID: entry.id, includingDeleted: false)

        #expect(read.map(\.order) == [0, 1])
        #expect(read.map(\.targetWeight) == [Weight(grams: 90_000), Weight(grams: 80_000)])
        #expect(read.map(\.targetReps) == [4, 5])
        #expect(read.map(\.targetSets) == [1, 3])
    }

    @Test("A blank target comes back blank rather than as a zero", arguments: Subject.all)
    func blankTargetSurvives(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let entry = try await seedEntry(in: repositories)
        try await repositories.plannedTargets.save(
            plannedTargetGroupRecord(exerciseEntryID: entry.id, grams: nil, reps: 5, sets: 5))

        let read = try await repositories.plannedTargets.plannedTargets(
            forEntryID: entry.id, includingDeleted: false)

        #expect(read.count == 1)
        // Anchored to `nil` on one side rather than compared to another optional: `nil == nil`
        // passes for a column that was never written at all.
        #expect(read.first?.targetWeight == nil)
        #expect(read.first?.targetReps == 5)
        #expect(read.first?.targetSets == 5)
    }

    @Test("A group naming no entry is refused", arguments: Subject.all)
    func danglingEntryIsRefused(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let group = plannedTargetGroupRecord(exerciseEntryID: UUID())

        await #expect(throws: RepositoryError.self) {
            try await repositories.plannedTargets.save(group)
        }
    }

    @Test("Deleting an exercise entry cascades to its planned targets", arguments: Subject.all)
    func deletingAnEntryCascades(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let entry = try await seedEntry(in: repositories)
        let group = plannedTargetGroupRecord(exerciseEntryID: entry.id)
        try await repositories.plannedTargets.save(group)

        // A second entry in the same session, whose plan must survive: a cascade keyed on the
        // session rather than on the entry would take it, and every assertion below would still
        // pass without it.
        let bystander = entryRecord(
            sessionID: entry.sessionID, exerciseID: entry.exerciseID, order: 1)
        try await repositories.workouts.save(bystander)
        try await repositories.plannedTargets.save(
            plannedTargetGroupRecord(exerciseEntryID: bystander.id))

        try await repositories.workouts.deleteExerciseEntry(id: entry.id)

        #expect(
            try await repositories.plannedTargets.plannedTargets(
                forEntryID: entry.id, includingDeleted: false
            ).isEmpty)
        #expect(
            try await repositories.plannedTargets.plannedTargets(
                forEntryID: entry.id, includingDeleted: true
            ).count == 1)
        #expect(
            try await repositories.plannedTargets.plannedTargets(
                forEntryID: bystander.id, includingDeleted: false
            ).count == 1)
    }

    @Test("Deleting the session cascades to every entry's planned targets", arguments: Subject.all)
    func deletingASessionCascades(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let entry = try await seedEntry(in: repositories)
        try await repositories.plannedTargets.save(
            plannedTargetGroupRecord(exerciseEntryID: entry.id))

        try await repositories.workouts.deleteSession(id: entry.sessionID)

        #expect(
            try await repositories.plannedTargets.plannedTargets(
                forEntryID: entry.id, includingDeleted: false
            ).isEmpty)
    }

    /// A session with one exercise in it, and the entry that names them both.
    private func seedEntry(in repositories: Repositories) async throws -> ExerciseEntry {
        let exercise = exerciseRecord()
        try await repositories.exercises.save(exercise)
        let session = sessionRecord()
        try await repositories.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id)
        try await repositories.workouts.save(entry)
        return entry
    }
}
