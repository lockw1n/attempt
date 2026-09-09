import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Logging

/// A session that is over, written straight into a store — what every past-session test starts from.
///
/// **Written rather than logged through ``ActiveSessionStore``**, and that is the point of it: this
/// screen's whole claim is that it needs no workout in progress, so a fixture that started one would
/// prove the opposite of what the tests are for.
struct PastSession {
    let repositories: InMemoryRepositoryStack
    let state: PastSessionState
    let sessionID: UUID
    let entries: [ExerciseEntry]
    let exercises: [Exercise]

    /// A fixed point in time, so nothing here depends on when the suite runs.
    static let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    /// Seeds a finished session with `names.count` exercises and returns the state over it.
    ///
    /// - Parameters:
    ///   - names: The exercises performed, in entry order.
    ///   - notes: The session's own note (`FR-1.2.9`).
    ///   - stamped: Whether it was a day of a program — what `FR-17.7.6` chooses the shape on.
    ///   - isFinished: Whether it has ended (`FR-17.9.8`). A day still being answered is on the
    ///     history list too, and `FR-17.7.3` reports no adherence for one.
    /// - Returns: The fixture.
    static func logged(
        names: [String] = ["Back Squat", "Bench Press", "Deadlift"],
        notes: String = "",
        stamped: Bool = false,
        isFinished: Bool = true
    ) async throws -> PastSession {
        let repositories = InMemoryRepositoryStack()
        let sessionID = UUID()
        try await repositories.workouts.save(
            session(id: sessionID, notes: notes, stamped: stamped, isFinished: isFinished))
        var exercises: [Exercise] = []
        var entries: [ExerciseEntry] = []
        for (order, name) in names.enumerated() {
            let exercise = Exercise.row(named: name)
            try await repositories.exercises.save(exercise)
            let entry = ExerciseEntry(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: sessionID,
                exerciseID: exercise.id,
                order: order,
                notes: ""
            )
            try await repositories.workouts.save(entry)
            exercises.append(exercise)
            entries.append(entry)
        }
        return PastSession(
            repositories: repositories,
            state: state(sessionID: sessionID, over: repositories),
            sessionID: sessionID,
            entries: entries,
            exercises: exercises
        )
    }

    /// A state over `repositories`, for a fixture that needs one built by hand.
    ///
    /// - Parameters:
    ///   - sessionID: The session it is about.
    ///   - repositories: What it reads.
    ///   - workouts: The workout repository to use, where it is not the stack's own — a double, say.
    /// - Returns: The state.
    static func state(
        sessionID: UUID,
        over repositories: InMemoryRepositoryStack,
        workouts: (any WorkoutRepository & PlannedTargetRepository)? = nil
    ) -> PastSessionState {
        let reader = workouts ?? repositories.workouts
        return PastSessionState(
            sessionID: sessionID,
            workouts: reader,
            catalogue: repositories.exercises,
            settings: repositories.settings,
            records: PersonalRecordRecomputer(
                workouts: reader,
                cache: repositories.personalRecords),
            trainingMaxes: repositories.trainingMaxes
        )
    }

    /// A finished session on a fixed day.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - notes: Its note.
    ///   - stamped: Whether it carries `FR-16.8.3`'s program position.
    ///   - isFinished: Whether it has ended.
    /// - Returns: The record.
    static func session(
        id: UUID, notes: String, stamped: Bool = false, isFinished: Bool = true
    ) -> WorkoutSession {
        WorkoutSession(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            date: stamp,
            startedAt: stamp,
            endedAt: isFinished ? stamp.addingTimeInterval(3600) : nil,
            notes: notes,
            bodyweight: nil,
            programRunID: stamped ? UUID() : nil,
            scheduledWorkoutID: nil,
            weekNumber: stamped ? 2 : nil,
            dayIndex: stamped ? 0 : nil
        )
    }

    /// Prescribes one group against the entry at `position` (`TR-15.3`).
    ///
    /// - Parameters:
    ///   - position: Which exercise it belongs to.
    ///   - order: Its place among that exercise's groups.
    ///   - weight: The load prescribed, or `nil` for `FR-15.2.2`'s blank.
    ///   - reps: The repetitions prescribed per set.
    ///   - sets: How many sets.
    /// - Returns: The stored group.
    @discardableResult
    func plan(
        at position: Int,
        order: Int = 0,
        weight: Weight? = Weight(grams: 100_000),
        reps: Int = 5,
        sets: Int = 5
    ) async throws -> PlannedTargetGroup {
        let group = PlannedTargetGroup(
            id: UUID(),
            createdAt: Self.stamp,
            updatedAt: Self.stamp,
            deletedAt: nil,
            exerciseEntryID: entries[position].id,
            order: order,
            targetWeight: weight,
            targetReps: reps,
            targetSets: sets
        )
        try await repositories.workouts.save(group)
        return group
    }

    /// Checks the entry at `position` off, as the lifter's answer does (`FR-17.9.3`).
    ///
    /// - Parameter position: Which exercise.
    func markDone(at position: Int) async throws {
        try await repositories.workouts.save(entries[position].markedDone)
    }

    /// The recomputer over this fixture's own store — what a set moving is announced to
    /// (`TR-1.6`), and where `FR-17.7.2`'s cache is written.
    var recomputer: PersonalRecordRecomputer {
        PersonalRecordRecomputer(
            workouts: repositories.workouts, cache: repositories.personalRecords)
    }

    /// Archives the exercise at `position` (`FR-1.1.5`), which is a soft delete (`G-1.3`).
    ///
    /// - Parameter position: Which exercise.
    func archiveExercise(at position: Int) async throws {
        let row = exercises[position]
        try await repositories.exercises.save(
            Exercise(
                id: row.id,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                deletedAt: Self.stamp,
                name: row.name,
                ukrainianName: row.ukrainianName,
                movement: row.movement,
                parentExerciseID: row.parentExerciseID,
                equipment: row.equipment,
                laterality: row.laterality,
                barType: row.barType,
                implementCount: row.implementCount,
                isCustom: row.isCustom,
                isArchived: true,
                notes: row.notes))
    }

    /// The entry at `position` as it is now stored.
    ///
    /// - Parameter position: Which exercise.
    /// - Returns: The row.
    func storedEntry(at position: Int) async throws -> ExerciseEntry? {
        try await repositories.workouts.entry(id: entries[position].id, includingDeleted: true)
    }

    /// Writes one set against the entry at `position`.
    ///
    /// - Parameters:
    ///   - position: Which exercise it belongs to.
    ///   - order: Its place among that exercise's sets.
    ///   - weight: The load.
    ///   - reps: The repetitions.
    ///   - isWarmup: Whether it is a warmup.
    ///   - isCompleted: Whether it was completed rather than failed.
    ///   - notes: `FR-1.2.3`'s per-set note.
    /// - Returns: The stored set.
    @discardableResult
    func logSet(
        at position: Int,
        order: Int,
        weight: Weight = Weight(grams: 100_000),
        reps: Int = 5,
        isWarmup: Bool = false,
        isCompleted: Bool = true,
        notes: String = ""
    ) async throws -> SetEntry {
        let set = SetEntry(
            id: UUID(),
            createdAt: Self.stamp,
            updatedAt: Self.stamp,
            deletedAt: nil,
            entryID: entries[position].id,
            order: order,
            weight: weight,
            reps: reps,
            rpe: nil,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: notes,
            completedAt: nil
        )
        try await repositories.workouts.save(set)
        return set
    }

    /// The sets stored against the entry at `position`, deleted ones included.
    ///
    /// - Parameter position: Which exercise to read.
    /// - Returns: Every row, whether or not it is soft-deleted.
    func storedSets(at position: Int) async throws -> [SetEntry] {
        try await repositories.workouts.sets(
            forEntryID: entries[position].id, includingDeleted: true)
    }
}

extension Exercise {
    /// A catalogue row with every field fixed but its name.
    ///
    /// - Parameter name: What it is called.
    /// - Returns: The row.
    static func row(named name: String) -> Exercise {
        // The same instant ``PastSession/stamp`` names, written again: this extension is nonisolated
        // and that property is not, the module compiling under `defaultIsolation(MainActor.self)`.
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return Exercise(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            name: name,
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: "")
    }
}
