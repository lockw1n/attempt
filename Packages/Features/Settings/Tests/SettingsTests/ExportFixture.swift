import Foundation
import Persistence
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Settings

/// The repositories a fixture writes through, whichever store is underneath.
///
/// **A type of its own rather than either stack**, because `DOD-1.3`'s round trip has to build the
/// same fixture twice — once over the fakes, where every other test here runs, and once over the
/// real SwiftData store, which is the only place `TR-1.14`'s purge exists. Two fixtures would be two
/// stores that could drift, and the drift would be invisible: the round trip would still pass, over
/// a store shaped differently from the one every other assertion in this suite is made against.
struct FixtureRepositories {
    /// The exercise catalogue and each exercise's training-max history.
    let exercises: any ExerciseRepository

    /// Sessions, entries, sets and their planned targets.
    let workouts: any WorkoutRepository & PlannedTargetRepository

    /// The single settings row (`TR-1.10`).
    let settings: any SettingsRepository

    /// The bodyweight log.
    let bodyweight: any BodyweightRepository

    /// The user's equipment profiles.
    let equipment: any EquipmentRepository

    /// The cached N-rep maxes (`TR-1.6`).
    let personalRecords: any PersonalRecordCacheRepository

    /// Routines, their exercise slots and target groups (`FR-15.2`).
    let routines: any RoutineRepository

    /// The fakes.
    ///
    /// - Parameter stack: The in-memory stack.
    init(_ stack: InMemoryRepositoryStack) {
        exercises = stack.exercises
        workouts = stack.workouts
        settings = stack.settings
        bodyweight = stack.bodyweight
        equipment = stack.equipment
        personalRecords = stack.personalRecords
        routines = stack.routines
    }

    /// The real store.
    ///
    /// - Parameter stack: The SwiftData stack.
    init(_ stack: PersistenceStack) {
        exercises = stack.exercises
        workouts = stack.workouts
        settings = stack.settings
        bodyweight = stack.bodyweight
        equipment = stack.equipment
        personalRecords = stack.personalRecords
        routines = stack.routines
    }
}

/// A store with a training log in it, written through the real fakes.
///
/// **Written, not stubbed**, for the reason History's fixture gives: the export's job is to walk
/// three levels joined by `UUID` columns, and a double that returned what a test handed it would
/// agree with any walk at all.
struct ExportLog {
    /// The repositories over one store — the fakes, or the real one where a test needs it.
    let repositories: FixtureRepositories

    /// A fixed instant everything is stamped from — one with a sub-second component, because the
    /// losslessness claim is about exactly that. It reads as 2025-07-06T00:00:00Z.
    static let epoch = Date(timeIntervalSinceReferenceDate: 773_452_800.123_456_7)

    /// A store with an empty catalogue and nothing logged.
    init() {
        repositories = FixtureRepositories(InMemoryRepositoryStack())
    }

    /// The same fixture over a real SwiftData store — `DOD-1.3`'s round trip and nothing else.
    ///
    /// - Parameter stack: The store to write into.
    init(_ stack: PersistenceStack) {
        repositories = FixtureRepositories(stack)
    }

    /// Writes an exercise into the catalogue.
    ///
    /// - Parameters:
    ///   - name: What it is called.
    ///   - id: Its identifier.
    /// - Returns: The record.
    @discardableResult
    func exercise(named name: String, id: UUID = UUID()) async throws -> Exercise {
        let exercise = ExportRecords.exercise(id: id, name: name, at: Self.epoch)
        try await repositories.exercises.save(exercise)
        return exercise
    }

    /// Writes a session that many days before the fixture's epoch.
    ///
    /// - Parameters:
    ///   - days: How many days before the epoch it was trained.
    ///   - id: Its identifier.
    ///   - notes: The session note.
    /// - Returns: The record.
    @discardableResult
    func session(
        daysAgo days: Int,
        id: UUID = UUID(),
        notes: String = ""
    ) async throws -> WorkoutSession {
        let session = ExportRecords.session(
            id: id,
            at: Self.epoch.addingTimeInterval(-Double(days) * 86_400),
            notes: notes)
        try await repositories.workouts.save(session)
        return session
    }

    /// Adds one exercise slot to a session.
    ///
    /// - Parameters:
    ///   - exercise: What was performed.
    ///   - session: Where it was performed.
    ///   - order: Its position in that session.
    ///   - notes: The slot's note.
    /// - Returns: The record.
    @discardableResult
    func entry(
        _ exercise: Exercise,
        in session: WorkoutSession,
        order: Int = 0,
        notes: String = ""
    ) async throws -> ExerciseEntry {
        let entry = ExportRecords.entry(
            sessionID: session.id,
            exerciseID: exercise.id,
            at: session.date,
            order: order,
            notes: notes)
        try await repositories.workouts.save(entry)
        return entry
    }

    /// Logs one set against an entry.
    ///
    /// - Parameters:
    ///   - entry: What it was performed under.
    ///   - order: Its position in that entry.
    ///   - grams: The load on one implement.
    ///   - reps: Repetitions performed.
    ///   - isWarmup: Whether it was a warmup.
    ///   - isCompleted: Whether it was actually performed.
    /// - Returns: The record.
    @discardableResult
    func set(
        in entry: ExerciseEntry,
        order: Int = 0,
        grams: Int,
        reps: Int,
        isWarmup: Bool = false,
        isCompleted: Bool = true
    ) async throws -> SetEntry {
        let set = ExportRecords.set(
            entryID: entry.id,
            at: Self.epoch,
            order: order,
            grams: grams,
            reps: reps,
            isWarmup: isWarmup,
            isCompleted: isCompleted)
        try await repositories.workouts.save(set)
        return set
    }

    /// Writes one bodyweight reading.
    ///
    /// - Parameters:
    ///   - grams: What the scale said.
    ///   - days: How many days before the epoch it was taken.
    /// - Returns: The record.
    @discardableResult
    func bodyweight(grams: Int, daysAgo days: Int = 0) async throws -> BodyweightEntry {
        let date = Self.epoch.addingTimeInterval(-Double(days) * 86_400)
        let entry = BodyweightEntry(
            id: UUID(),
            createdAt: date,
            updatedAt: date,
            deletedAt: nil,
            date: date,
            weight: Weight(grams: grams),
            source: .manual)
        try await repositories.bodyweight.save(entry)
        return entry
    }

    /// Sets the unit the CSV is written in.
    ///
    /// - Parameter unit: The unit to read in.
    func setDisplayUnit(_ unit: MassUnit) async throws {
        var settings = try await repositories.settings.settings()
        settings.displayUnit = unit
        try await repositories.settings.save(settings)
    }

    /// The export over these fakes.
    var export: TrainingLogExport {
        TrainingLogExport(
            exercises: repositories.exercises,
            workouts: repositories.workouts,
            bodyweight: repositories.bodyweight)
    }

    /// A store with one session, one exercise and three sets — the shape most tests here want.
    ///
    /// - Parameter log: Which store to write into, defaulting to a fresh set of fakes.
    /// - Returns: The populated fixture.
    static func populated(_ log: ExportLog = ExportLog()) async throws -> ExportLog {
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(daysAgo: 0, notes: "felt good")
        let entry = try await log.entry(squat, in: session)
        _ = try await log.set(in: entry, order: 0, grams: 60_000, reps: 5, isWarmup: true)
        _ = try await log.set(in: entry, order: 1, grams: 102_500, reps: 5)
        _ = try await log.set(in: entry, order: 2, grams: 102_500, reps: 0, isCompleted: false)
        return log
    }
}

/// Records as values, written to nothing — what a test builds when it is asserting on the shape of
/// a file rather than on what a store did with a row.
enum ExportRecords {
    /// A deterministic identifier, ordered by `byte` under the string comparison the CSV's session
    /// tiebreak uses. **Not `UUID(uuidString:)`**, which is optional and would need force-unwrapping
    /// at every call site the lint rules forbid it at.
    ///
    /// - Parameter byte: What to vary. Everything else is fixed.
    /// - Returns: The identifier.
    static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0))
    }

    /// One exercise.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - name: What it is called.
    ///   - at: When it was written.
    ///   - parentExerciseID: The exercise this is a variation of (`FR-1.1.7`), or `nil`.
    /// - Returns: The record.
    static func exercise(
        id: UUID = UUID(),
        name: String,
        at stamp: Date,
        parentExerciseID: UUID? = nil
    ) -> Exercise {
        Exercise(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            name: name,
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: parentExerciseID,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: true,
            isArchived: false,
            notes: "",
            manualE1RM: nil)
    }

    /// One session.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - at: The training day, which is also when the row was written.
    ///   - notes: The session note.
    /// - Returns: The record.
    static func session(id: UUID = UUID(), at date: Date, notes: String = "") -> WorkoutSession {
        WorkoutSession(
            id: id,
            createdAt: date,
            updatedAt: date,
            deletedAt: nil,
            date: date,
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            notes: notes,
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil)
    }

    /// One exercise slot.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - sessionID: The session it belongs to.
    ///   - exerciseID: What was performed.
    ///   - at: When it was written.
    ///   - order: Its position in the session.
    ///   - notes: The slot's note.
    /// - Returns: The record.
    static func entry(
        id: UUID = UUID(),
        sessionID: UUID,
        exerciseID: UUID,
        at stamp: Date,
        order: Int = 0,
        notes: String = ""
    ) -> ExerciseEntry {
        ExerciseEntry(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            sessionID: sessionID,
            exerciseID: exerciseID,
            order: order,
            notes: notes)
    }

    /// One set.
    ///
    /// - Parameters:
    ///   - entryID: The slot it belongs to.
    ///   - at: When it was written.
    ///   - order: Its position in the slot.
    ///   - grams: The load on one implement.
    ///   - reps: Repetitions performed.
    ///   - rpe: What it was rated, if anything.
    ///   - rir: How many were left, if recorded.
    ///   - isWarmup: Whether it was a warmup.
    ///   - isCompleted: Whether it was actually performed.
    ///   - modifiers: What was worn or done differently.
    ///   - notes: The set's own note.
    /// - Returns: The record.
    static func set(
        entryID: UUID,
        at stamp: Date,
        order: Int = 0,
        grams: Int = 100_000,
        reps: Int = 5,
        rpe: Double? = nil,
        rir: Int? = nil,
        isWarmup: Bool = false,
        isCompleted: Bool = true,
        modifiers: [SetModifier] = [],
        notes: String = ""
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            entryID: entryID,
            order: order,
            weight: Weight(grams: grams),
            reps: reps,
            rpe: rpe,
            rir: rir,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: modifiers,
            notes: notes,
            completedAt: nil)
    }
}

/// A scratch directory for a test that writes files, removed when the test lets it go.
final class ScratchDirectory: Sendable {
    /// Where the files go.
    let url: URL

    /// Makes a directory nothing else is using.
    init() {
        url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)")
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
