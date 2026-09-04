import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// Rule 7: a save stamps `updatedAt`, ignores the record's `deletedAt`, and honours `createdAt`
/// only when the row is new (`G-1.2`, `G-2.4`, `FR-1.11.3`).
///
/// **The half a fake gets wrong by storing what it is handed**, and the half a caller's own tests
/// cannot notice: every timestamp is plausible either way.
@Suite("Conformance — the audit columns belong to the write path")
struct AuditColumnConformanceTests {
    @Test("A save stamps updatedAt whatever the record claimed", arguments: Subject.all)
    func aSaveStampsUpdatedAt(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        try await repositories.exercises.save(exerciseRecord(id: id, name: "Squat"))

        let stored = try #require(
            try await repositories.exercises.exercise(id: id, includingDeleted: false))
        #expect(stored.updatedAt > fixtureUpdatedAt)
    }

    @Test("A save honours createdAt on a new row and leaves it alone afterwards", arguments: Subject.all)
    func createdAtBelongsToTheInsert(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        let arrived = Date(timeIntervalSince1970: 1_500_000_000)
        try await repositories.exercises.save(
            exerciseRecord(id: id, name: "Squat", createdAt: arrived))

        // The insert kept the history the record arrived with — that is FR-1.11.3's restore.
        #expect(
            try await repositories.exercises.exercise(id: id, includingDeleted: false)?.createdAt
                == arrived)

        // …and a later edit claiming a different history does not relabel it.
        try await repositories.exercises.save(
            exerciseRecord(id: id, name: "Back Squat", createdAt: Date(timeIntervalSince1970: 0)))
        let updated = try #require(
            try await repositories.exercises.exercise(id: id, includingDeleted: false))
        #expect(updated.createdAt == arrived)
        #expect(updated.name == "Back Squat")
    }

    @Test("A save ignores the record's deletedAt and stores a live row", arguments: Subject.all)
    func aSaveCannotDelete(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()

        try await repositories.bodyweight.save(
            bodyweightRecord(id: id, deletedAt: Date(timeIntervalSince1970: 0)))

        let stored = try #require(
            try await repositories.bodyweight.entry(id: id, includingDeleted: false))
        #expect(stored.deletedAt == nil)
    }

    @Test("A save over a deleted row writes it and does not resurrect it", arguments: Subject.all)
    func aSaveIsNotAnUndelete(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        try await repositories.bodyweight.save(bodyweightRecord(id: id, grams: 80_000))
        try await repositories.bodyweight.deleteEntry(id: id)

        try await repositories.bodyweight.save(bodyweightRecord(id: id, grams: 81_000))

        #expect(try await repositories.bodyweight.entry(id: id, includingDeleted: false) == nil)
        let stored = try #require(
            try await repositories.bodyweight.entry(id: id, includingDeleted: true))
        #expect(stored.weight == Weight(grams: 81_000))
        #expect(stored.deletedAt != nil)
    }

    @Test("A save upserts on id rather than appending a second row", arguments: Subject.all)
    func aSaveUpserts(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        try await repositories.exercises.save(exerciseRecord(id: id, name: "Squat"))
        try await repositories.exercises.save(exerciseRecord(id: id, name: "Back Squat"))

        let all = try await repositories.exercises.exercises(includingDeleted: true)
        #expect(all.map(\.name) == ["Back Squat"])
    }

    @Test("Every write path stamps, not just the exercise one", arguments: Subject.all)
    func stampingIsNotOneRepositorysHabit(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        let setID = UUID()
        try await repositories.workouts.save(setRecord(id: setID, entryID: timeline.entryID))
        try await repositories.bodyweight.save(bodyweightRecord())
        try await repositories.equipment.save(profileRecord())
        try await repositories.trainingMaxes.save(
            trainingMaxHistoryRecord(exerciseID: timeline.exerciseID, effectiveFrom: fixtureCreatedAt))
        let routine = routineRecord()
        try await repositories.routines.save(routine)
        let slot = routineExerciseRecord(
            routineID: routine.id, exerciseID: timeline.exerciseID)
        try await repositories.routines.save(slot)
        try await repositories.routines.save(routineTargetGroupRecord(routineExerciseID: slot.id))

        let session = try #require(
            try await repositories.workouts.session(
                id: timeline.sessionID, includingDeleted: false))
        let entry = try #require(
            try await repositories.workouts.entries(
                forSessionID: timeline.sessionID, includingDeleted: false
            ).first)
        let set = try #require(
            try await repositories.workouts.sets(
                forEntryID: timeline.entryID, includingDeleted: false
            ).first)
        let weight = try #require(
            try await repositories.bodyweight.entries(
                in: fixtureCreatedAt...fixtureCreatedAt, includingDeleted: false
            ).first)
        let profile = try #require(
            try await repositories.equipment.profiles(includingDeleted: false).first)
        let trainingMax = try #require(
            try await repositories.trainingMaxes.trainingMax(
                forExerciseID: timeline.exerciseID, on: fixtureCreatedAt))
        let storedRoutine = try #require(
            try await repositories.routines.routine(id: routine.id, includingDeleted: false))
        let storedSlot = try #require(
            try await repositories.routines.exercises(
                forRoutineID: routine.id, includingDeleted: false
            ).first)
        let storedGroup = try #require(
            try await repositories.routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false
            ).first)

        for stamped in [
            session.updatedAt, entry.updatedAt, set.updatedAt,
            weight.updatedAt, profile.updatedAt, trainingMax.updatedAt,
            storedRoutine.updatedAt, storedSlot.updatedAt, storedGroup.updatedAt,
        ] {
            #expect(stamped > fixtureUpdatedAt)
        }
    }

    /// The seventh write path, and the reason it is a separate test rather than a seventh line in
    /// the loop above.
    ///
    /// `SettingsRepository` has no insert a caller can distinguish from an update, so proving the
    /// stamp needs both branches taken separately — and the loop's shape (compare against the
    /// literal the record carried) is only exact for the *insert*. On the update branch the stored
    /// row already holds a bootstrap `Date.now`, so `> fixtureUpdatedAt` passes whether the save
    /// stamps or not; a probe survived on exactly that, and it is the one write path whose
    /// `updatedAt` neither suite asserted.
    @Test("The settings save stamps updatedAt on both of its branches", arguments: Subject.all)
    func theSettingsSaveStampsToo(_ subject: Subject) async throws {
        let repositories = try subject.make()

        // Insert: a save into an empty store, which is `FR-1.11.3`'s restore. Exact, against the
        // literal the record carried.
        try await repositories.settings.save(settingsRecord(userID: UUID()))
        let inserted = try await repositories.settings.settings()
        #expect(inserted.updatedAt > fixtureUpdatedAt)

        // Update: the row is already there, so the claim can only be "it moved". No column here is
        // written from the same instant, unlike a delete's `deletedAt`, so this one is a comparison
        // — the two `Date.now` readings are an actor hop and a whole read apart.
        try await repositories.settings.save(
            settingsRecord(
                userID: inserted.userID, displayUnit: .kilograms, roundingIncrementGrams: 2500))
        let updated = try await repositories.settings.settings()
        #expect(updated.updatedAt > inserted.updatedAt)
        #expect(updated.displayUnit == .kilograms)
    }

    /// The modifier column's storage contract, which is the other thing a fake gets wrong by
    /// keeping what it was handed.
    ///
    /// A logged modifier is the user's own data and is never degraded, but the *list* is a set:
    /// stored deduplicated and sorted by spelling, so two records differing only in the order they
    /// listed the same modifiers read back identically.
    @Test("A set's modifiers are stored deduplicated and sorted", arguments: Subject.all)
    func modifiersAreCanonicalisedOnTheWayIn(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        let id = UUID()

        try await repositories.workouts.save(
            setRecord(
                id: id,
                entryID: timeline.entryID,
                modifiers: [
                    SetModifier(.paused), SetModifier(.belt), SetModifier(.paused),
                    SetModifier(rawValue: "chains"),
                ]
            ))

        let stored = try #require(
            try await repositories.workouts.sets(
                forEntryID: timeline.entryID, includingDeleted: false
            ).first)
        #expect(stored.modifiers.map(\.rawValue) == ["belt", "chains", "paused"])

        // **The second save, on the row that already exists.** Insert and update are different
        // writers on the store side — the entity's initialiser and `replaceModifiers(with:)` — and
        // a probe survived when only the insert path was covered here. An edit is also the likelier
        // path in the app: a set is logged first and modified afterwards.
        try await repositories.workouts.save(
            setRecord(
                id: id,
                entryID: timeline.entryID,
                modifiers: [SetModifier(.wraps), SetModifier(.belt), SetModifier(.wraps)]
            ))

        let edited = try #require(
            try await repositories.workouts.sets(
                forEntryID: timeline.entryID, includingDeleted: false
            ).first)
        #expect(edited.modifiers.map(\.rawValue) == ["belt", "wraps"])
    }
}
