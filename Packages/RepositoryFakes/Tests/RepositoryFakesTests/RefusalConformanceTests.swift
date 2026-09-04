import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// What a repository refuses, and what it must not refuse.
///
/// `G-2.5` declares no relationships, so nothing but this layer would ever notice a join key
/// pointing at nothing — and afterwards a dangling reference is indistinguishable from a real one.
@Suite("Conformance — refusals")
struct RefusalConformanceTests {
    @Test("A variation whose parent is not there is refused; saved after it, it is stored", arguments: Subject.all)
    func aVariationNeedsItsParent(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let parentID = UUID()
        let variation = exerciseRecord(name: "Pause Squat", parentExerciseID: parentID)

        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: variation.id, referencing: parentID)
        ) { try await repositories.exercises.save(variation) }
        #expect(try await repositories.exercises.exercises(includingDeleted: true).isEmpty)

        try await repositories.exercises.save(exerciseRecord(id: parentID))
        try await repositories.exercises.save(variation)
        #expect(try await repositories.exercises.exercises(includingDeleted: false).count == 2)
    }

    @Test("An exercise naming itself as its parent is refused, before and after it exists", arguments: Subject.all)
    func anExerciseCannotBeItsOwnParent(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        let selfParenting = exerciseRecord(id: id, parentExerciseID: id)

        await #expect(
            throws: RepositoryError.danglingReference(recordID: id, referencing: id)
        ) { try await repositories.exercises.save(selfParenting) }

        // …and still refused once the row exists, which existence alone would have accepted.
        try await repositories.exercises.save(exerciseRecord(id: id))
        await #expect(
            throws: RepositoryError.danglingReference(recordID: id, referencing: id)
        ) { try await repositories.exercises.save(selfParenting) }

        #expect(
            try await repositories.exercises.exercises(includingDeleted: true)
                .map(\.parentExerciseID) == [nil])
    }

    @Test("An entry needs both its session and its exercise", arguments: Subject.all)
    func anEntryNeedsBothOfItsJoinKeys(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let sessionID = UUID()
        let exerciseID = UUID()
        try await repositories.workouts.save(sessionRecord(id: sessionID))
        let orphan = entryRecord(sessionID: sessionID, exerciseID: exerciseID)

        await #expect(
            throws: RepositoryError.danglingReference(recordID: orphan.id, referencing: exerciseID)
        ) { try await repositories.workouts.save(orphan) }

        let unsessioned = entryRecord(sessionID: UUID(), exerciseID: exerciseID)
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: unsessioned.id, referencing: unsessioned.sessionID)
        ) { try await repositories.workouts.save(unsessioned) }
    }

    @Test("A set needs its entry", arguments: Subject.all)
    func aSetNeedsItsEntry(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let entryID = UUID()
        let orphan = setRecord(entryID: entryID)

        await #expect(
            throws: RepositoryError.danglingReference(recordID: orphan.id, referencing: entryID)
        ) { try await repositories.workouts.save(orphan) }
    }

    /// The one case that looks like a refusal and is not.
    ///
    /// The question a join key asks is whether the row exists. Requiring a *live* target would make
    /// re-saving a set inside a deleted session throw `danglingReference`, which names a different
    /// fault entirely — and the cascade puts sessions and entries into exactly that state.
    @Test("A soft-deleted target is not a dangling reference", arguments: Subject.all)
    func aDeletedTargetStillExists(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        try await repositories.workouts.deleteSession(id: timeline.sessionID)

        let id = UUID()
        try await repositories.workouts.save(setRecord(id: id, entryID: timeline.entryID))

        let stored = try #require(
            try await repositories.workouts.sets(
                forEntryID: timeline.entryID, includingDeleted: false
            ).first)
        #expect(stored.id == id)
        #expect(stored.deletedAt == nil)
    }

    @Test("A training max needs its exercise", arguments: Subject.all)
    func aTrainingMaxNeedsItsExercise(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let entry = trainingMaxHistoryRecord(exerciseID: UUID(), effectiveFrom: fixtureCreatedAt)

        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: entry.id, referencing: entry.exerciseID)
        ) { try await repositories.trainingMaxes.save(entry) }

        #expect(
            try await repositories.trainingMaxes.history(
                forExerciseID: entry.exerciseID, includingDeleted: true
            ).isEmpty)
    }

    /// The same edge on the other table, and it needs its own case: the two saves check the
    /// reference separately in both implementations, so one test leaves the other guard unheld.
    ///
    /// The guard this names is the exercise check, and the arrangement reaches it — the store is
    /// empty, so there is no earlier guard for the save to stop at.
    @Test("A training-max configuration needs its exercise", arguments: Subject.all)
    func aConfigurationNeedsItsExercise(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let entry = trainingMaxRecord(exerciseID: UUID(), effectiveFrom: fixtureCreatedAt)

        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: entry.id, referencing: entry.exerciseID)
        ) { try await repositories.trainingMaxes.saveConfiguration(entry) }

        #expect(
            try await repositories.trainingMaxes.configurationHistory(
                forExerciseID: entry.exerciseID, includingDeleted: true
            ).isEmpty)
    }

    /// **Every delete on every protocol, and the count in the name is load-bearing.**
    ///
    /// This test was called "on all four deletes" while its body exercised five, and then a
    /// protocol arrived with three more and neither the name nor the body noticed. A number in a
    /// test name is a claim about a set, so it goes stale exactly when a member is added — which
    /// is the moment the test most needs to be looked at.
    @Test("Deleting a row that was never there is refused, on all eight deletes", arguments: Subject.all)
    func aMissingRowCannotBeDeleted(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()

        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.workouts.deleteSession(id: id)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.workouts.deleteExerciseEntry(id: id)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.workouts.deleteSet(id: id)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.bodyweight.deleteEntry(id: id)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.equipment.deleteProfile(id: id)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.routines.deleteRoutine(id: id)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.routines.deleteRoutineExercise(id: id)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.routines.deleteTargetGroup(id: id)
        }
    }

    @Test("A read of a row that was never there answers nil rather than throwing", arguments: Subject.all)
    func aMissingRowReadsAsNil(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()

        #expect(try await repositories.exercises.exercise(id: id, includingDeleted: true) == nil)
        #expect(try await repositories.workouts.session(id: id, includingDeleted: true) == nil)
        #expect(try await repositories.bodyweight.entry(id: id, includingDeleted: true) == nil)
        #expect(try await repositories.equipment.profile(id: id, includingDeleted: true) == nil)
        #expect(try await repositories.equipment.defaultProfile() == nil)
        #expect(
            try await repositories.trainingMaxes.trainingMax(forExerciseID: id, on: fixtureCreatedAt)
                == nil)
    }

    /// The write path's half of rule 4.
    ///
    /// A record does not validate and a read returns a malformed row whole — that is what makes
    /// `FR-1.11.3` able to export one for repair. A row *authored* on this device has no such
    /// excuse, and without this refusal the failure would land later, inside `PlateCalculator`, on
    /// a screen far from the one that stored it.
    /// **Both malformed shapes are pinned to `unusableRecord`, not merely to "something threw".**
    ///
    /// `RepositoryError`'s contract is that only this case names a row the caller must repair, so a
    /// refusal arriving as `recordNotFound` — or as a store failure surfacing from somewhere else
    /// inside `save` — would route a caller's error handling wrongly. Asserting `(any Error).self`
    /// on the second fixture said the profile was refused without saying what for.
    @Test("A profile whose plate lists cannot describe a gym is refused", arguments: Subject.all)
    func aProfileIsProjectedBeforeItIsStored(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let repeated = profileRecord(plates: [25_000, 25_000], pairCounts: [2, 2])
        let mismatched = profileRecord(plates: [25_000, 20_000], pairCounts: [2])

        for malformed in [repeated, mismatched] {
            let error = await #expect(throws: RepositoryError.self) {
                try await repositories.equipment.save(malformed)
            }
            guard case .unusableRecord(let recordID, _) = error else {
                Issue.record("expected unusableRecord, got \(String(describing: error))")
                continue
            }
            #expect(recordID == malformed.id)
        }

        #expect(try await repositories.equipment.profiles(includingDeleted: true).isEmpty)
    }
}
