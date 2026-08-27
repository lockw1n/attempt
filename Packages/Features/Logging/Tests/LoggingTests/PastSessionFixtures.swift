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
    /// - Returns: The fixture.
    static func logged(
        names: [String] = ["Back Squat", "Bench Press", "Deadlift"], notes: String = ""
    ) async throws -> PastSession {
        let repositories = InMemoryRepositoryStack()
        let sessionID = UUID()
        try await repositories.workouts.save(session(id: sessionID, notes: notes))
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
        workouts: (any WorkoutRepository)? = nil
    ) -> PastSessionState {
        let reader = workouts ?? repositories.workouts
        return PastSessionState(
            sessionID: sessionID,
            workouts: reader,
            catalogue: repositories.exercises,
            settings: repositories.settings,
            records: PersonalRecordRecomputer(
                workouts: reader,
                exercises: InMemoryRepositoryStack().exercises,
                cache: repositories.personalRecords)
        )
    }

    /// A finished session on a fixed day.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - notes: Its note.
    /// - Returns: The record.
    static func session(id: UUID, notes: String) -> WorkoutSession {
        WorkoutSession(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            date: stamp,
            startedAt: stamp,
            endedAt: stamp.addingTimeInterval(3600),
            notes: notes,
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
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
    /// - Returns: The stored set.
    @discardableResult
    func logSet(
        at position: Int,
        order: Int,
        weight: Weight = Weight(grams: 100_000),
        reps: Int = 5,
        isWarmup: Bool = false,
        isCompleted: Bool = true
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
            notes: "",
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
}

/// A workout repository that answers from a real one until it is told to refuse.
///
/// **Two switches rather than a second refusing double**, and the reason is what the refusals are
/// claimed to do. Both ``PastSessionState/phase``'s failed case and ``PastSessionState/writeFailure``
/// are assertions about rows that were *on screen first* — one costs the screen them, the other
/// leaves every one exactly as it was. A double that refuses from the start cannot tell those apart
/// from a screen that never had rows at all, which is true of an empty state either way.
///
/// **An actor** (`G-6.4`): `WorkoutRepository` refines `Sendable`, which leaves a class holding
/// switches the choice between `@unchecked Sendable` and an isolated conformance the compiler
/// refuses for a `Sendable` protocol. The switches are flipped through methods for the same reason.
actor FailableWorkoutRepository: WorkoutRepository {
    /// Whether reads are turned down from here on.
    private var refusesReads = false

    /// Whether writes are, and deletions with them.
    private var refusesWrites = false

    /// Whether the session's *entry* read is, on its own.
    ///
    /// The one call ``PastSessionState`` makes on the way to rebuilding its rows and
    /// ``LoggedSetWriter`` never makes at all — so this refuses the re-read behind a correction
    /// while letting the correction itself through, which is the only way to reach the case where
    /// a change is stored and the screen cannot show it.
    private var refusesEntryReads = false

    /// Starts refusing every read.
    func refuseReads() { refusesReads = true }

    /// Starts or stops refusing every write.
    ///
    /// - Parameter refuses: Whether writes are turned down from here on.
    func refuseWrites(_ refuses: Bool = true) { refusesWrites = refuses }

    /// Starts refusing the entry read alone — see ``refusesEntryReads``.
    func refuseEntryReads() { refusesEntryReads = true }

    /// What the reads are answered from while they are allowed.
    private let wrapped: any WorkoutRepository

    /// What a refusal raises.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    /// Builds the double over a real repository.
    ///
    /// - Parameter wrapped: What answers while nothing is refused.
    init(wrapping wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        if refusesReads { throw failure }
        return try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        if refusesReads { throw failure }
        return try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        if refusesReads || refusesEntryReads { throw failure }
        return try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        if refusesReads { throw failure }
        return try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        if refusesReads { throw failure }
        return try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws {
        if refusesWrites { throw failure }
        try await wrapped.save(session)
    }
    /// Honours ``refuseReads()`` but **not** `refusesEntryReads`, which is about the entries-of-a-
    /// session read specifically. This one is the recompute's, and it is not what that flag is for.
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        if refusesReads { throw failure }
        return try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }

    func save(_ entry: ExerciseEntry) async throws {
        if refusesWrites { throw failure }
        try await wrapped.save(entry)
    }
    func save(_ set: SetEntry) async throws {
        if refusesWrites { throw failure }
        try await wrapped.save(set)
    }
    func deleteSession(id: UUID) async throws {
        if refusesWrites { throw failure }
        try await wrapped.deleteSession(id: id)
    }
    func deleteExerciseEntry(id: UUID) async throws {
        if refusesWrites { throw failure }
        try await wrapped.deleteExerciseEntry(id: id)
    }
    func deleteSet(id: UUID) async throws {
        if refusesWrites { throw failure }
        try await wrapped.deleteSet(id: id)
    }
}

/// A workout repository that stops one entry read until a test lets it go, counting them all.
///
/// `SessionListPagingTests`' gate, narrowed to the one read this screen makes per load: the
/// rendezvous is what makes the in-flight guard testable rather than a race — ``arrival()`` returns
/// once the held read is suspended *inside* the gate, so a second `load()` is issued at a moment
/// when the first is provably still out. ``entryReads`` is the assertion, because a refused load
/// and a load whose result is discarded look identical from the outside.
///
/// **An actor for ``FailableWorkoutRepository``'s reason** (`G-6.4`), which is also what makes the
/// rendezvous' own state safe to touch from the test while a read is suspended in it.
actor GatedWorkoutRepository: WorkoutRepository {
    /// How many entry reads have been answered.
    private(set) var entryReads = 0

    private let wrapped: any WorkoutRepository
    private var hasHeld = false
    private var arrived: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?

    /// Builds the gate over a real repository. The first entry read is the one held.
    ///
    /// - Parameter wrapped: What the reads are answered from.
    init(wrapping wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    /// Suspends until the held read has reached the gate.
    func arrival() async {
        guard !hasHeld else { return }
        await withCheckedContinuation { arrived = $0 }
    }

    /// Lets the held read continue.
    func release() {
        waiting?.resume()
        waiting = nil
    }

    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        entryReads += 1
        if !hasHeld {
            hasHeld = true
            await withCheckedContinuation { continuation in
                waiting = continuation
                arrived?.resume()
                arrived = nil
            }
        }
        return try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws { try await wrapped.deleteExerciseEntry(id: id) }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}

/// A workout repository that refuses everything, for the failed-read and failed-write states.
struct RefusingWorkoutRepository: WorkoutRepository {
    /// What every call raises.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] { throw failure }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { throw failure }
    func save(_ session: WorkoutSession) async throws { throw failure }
    func deleteSession(id: UUID) async throws { throw failure }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] { throw failure }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { throw failure }
    func save(_ entry: ExerciseEntry) async throws { throw failure }
    func deleteExerciseEntry(id: UUID) async throws { throw failure }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }
    func save(_ set: SetEntry) async throws { throw failure }
    func deleteSet(id: UUID) async throws { throw failure }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }
}
