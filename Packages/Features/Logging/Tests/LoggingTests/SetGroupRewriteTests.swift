import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// Rewriting a whole answered group (`FR-17.7.5`, `FR-17.1.3`'s rewrite in the sheet's shape).
///
/// **Three shapes of change and one non-change**, and each is a different write: a member that
/// moved, a count that came down, a count that went up, and a group saved untouched — which must
/// write nothing at all, `updatedAt` being `G-2.4`'s conflict key.
@MainActor
@Suite("Rewriting a group")
struct SetGroupRewriteTests {
    @Test("A changed load reaches every member, and the rows keep their identities")
    func aChangedLoadReachesEveryMember() async throws {
        let group = try await Group.of(5, at: 80_000, reps: 5)

        let changed = try await group.rewrite(to: group.rows(at: 82_500, reps: 5, count: 5))

        #expect(changed)
        let stored = try await group.stored()
        #expect(stored.count == 5)
        #expect(stored.allSatisfy { $0.weight == Weight(grams: 82_500) })
        // Matched by position rather than by shape, so nothing lost its `createdAt` or its outcome.
        #expect(stored.map(\.id) == group.identifiers)
    }

    @Test("A lowered count soft-deletes the trailing rows and rewrites nothing else")
    func aLoweredCountRemovesTheTail() async throws {
        let group = try await Group.of(5, at: 80_000, reps: 5)
        let before = try await group.timestamps()

        let changed = try await group.rewrite(to: group.rows(at: 80_000, reps: 5, count: 3))

        #expect(changed)
        let stored = try await group.stored()
        #expect(stored.count == 3)
        #expect(stored.map(\.id) == Array(group.identifiers.prefix(3)))
        // The three that survived were not written: their conflict key has not moved.
        #expect(stored.map(\.updatedAt) == Array(before.prefix(3)))
        // Soft, like every deletion here (`G-1.3`) — the rows are still in the store.
        #expect(try await group.stored(includingDeleted: true).count == 5)
    }

    @Test("A raised count appends, in order and after the last row")
    func aRaisedCountAppends() async throws {
        let group = try await Group.of(3, at: 80_000, reps: 5)

        let changed = try await group.rewrite(to: group.rows(at: 80_000, reps: 5, count: 4))

        #expect(changed)
        let stored = try await group.stored()
        #expect(stored.count == 4)
        #expect(Array(stored.prefix(3)).map(\.id) == group.identifiers)
        #expect(stored.map(\.order) == [0, 1, 2, 3])
        // The Log sheet answers "what did you do", so every row it writes is work that happened.
        #expect(stored.allSatisfy { $0.isCompleted })
        // `FR-15.3.5`: the plan is never copied onto an answer.
        #expect(stored.allSatisfy { $0.targetWeight == nil && $0.targetReps == nil })
    }

    @Test("A group saved untouched writes nothing, so no local no-op outranks a remote edit")
    func anUnchangedGroupWritesNothing() async throws {
        let group = try await Group.of(3, at: 80_000, reps: 5)
        let before = try await group.timestamps()

        let changed = try await group.rewrite(to: group.rows(at: 80_000, reps: 5, count: 3))

        #expect(!changed)
        #expect(try await group.timestamps() == before)
    }

    @Test("Per-set reps reach the rows they belong to and nothing else moves")
    func perSetRepsReachTheirOwnRows() async throws {
        let group = try await Group.of(3, at: 80_000, reps: 8)

        try await group.rewrite(
            to: [8, 8, 6].map {
                SetEntryValues(weight: Weight(grams: 80_000), reps: $0, rpe: nil, isWarmup: false)
            })

        let stored = try await group.stored()
        #expect(stored.map(\.reps) == [8, 8, 6])
        #expect(stored.map(\.id) == group.identifiers)
    }

    // MARK: - NFR-1.8: what a refusal part-way through keeps

    @Test("A refused write on the third of five rows keeps the first two, and reports once")
    func aRefusalKeepsWhatLanded() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entryID = try #require(workout.store.exercises.first).id
        let refusing = SetWriteRefusingRepository(
            wrapped: workout.repositories.workouts, refusingFrom: 2)
        let store = ActiveSessionStore.over(workout.repositories, workouts: refusing)
        await store.adopt(sessionID: try #require(workout.store.session).id)
        await store.loadExercises()

        await store.logGroup(
            inEntryID: entryID,
            rows: (0..<5).map { _ in
                SetEntryValues(weight: Weight(grams: 80_000), reps: 5, rpe: nil, isWarmup: false)
            })

        // Every row written before the refusal stays written — nothing is rolled back.
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        #expect(stored.count == 2)
        // Reported once, as one diagnostic rather than three.
        #expect(store.exercisesWriteFailure != nil)
        // And the row is not marked done: the chain stopped before the mark.
        let entries = try await workout.repositories.workouts.entries(
            forSessionID: try #require(workout.store.session).id, includingDeleted: false)
        #expect(entries.first?.isMarkedDone == false)
    }

    /// One entry with a group of identical sets already logged against it.
    private struct Group {
        let workout: Workout
        let entryID: UUID
        let identifiers: [UUID]

        /// Logs `count` identical sets and returns the group they form.
        ///
        /// - Parameters:
        ///   - count: How many.
        ///   - grams: The load.
        ///   - reps: The repetitions.
        /// - Returns: The group.
        static func of(_ count: Int, at grams: Int, reps: Int) async throws -> Group {
            let workout = try await Workout.started()
            for _ in 0..<count {
                _ = try await workout.logSet(
                    SetEntryValues(
                        weight: Weight(grams: grams), reps: reps, rpe: nil, isWarmup: false))
            }
            let entryID = try #require(workout.store.exercises.first).id
            let stored = try await workout.repositories.workouts.sets(
                forEntryID: entryID, includingDeleted: false)
            return Group(workout: workout, entryID: entryID, identifiers: stored.map(\.id))
        }

        /// `count` rows of the same shape.
        ///
        /// - Parameters:
        ///   - grams: The load.
        ///   - reps: The repetitions.
        ///   - count: How many.
        /// - Returns: The rows.
        func rows(at grams: Int, reps: Int, count: Int) -> [SetEntryValues] {
            (0..<count).map { _ in
                SetEntryValues(
                    weight: Weight(grams: grams), reps: reps, rpe: nil, isWarmup: false)
            }
        }

        /// Runs the rewrite.
        ///
        /// - Parameter rows: What the group becomes.
        /// - Returns: Whether anything was written.
        @discardableResult
        func rewrite(to rows: [SetEntryValues]) async throws -> Bool {
            try await SetGroupRewrite(
                repository: workout.repositories.workouts,
                records: PersonalRecordRecomputer(
                    workouts: workout.repositories.workouts,
                    cache: workout.repositories.personalRecords)
            )
            .rewrite(inEntryID: entryID, to: rows)
        }

        /// The entry's sets, in order.
        ///
        /// - Parameter includingDeleted: Whether the soft-deleted ones count.
        /// - Returns: The rows.
        func stored(includingDeleted: Bool = false) async throws -> [SetEntry] {
            try await workout.repositories.workouts
                .sets(forEntryID: entryID, includingDeleted: includingDeleted)
                .sorted { $0.order < $1.order }
        }

        /// Each stored row's `updatedAt`, in order — `G-2.4`'s conflict key.
        ///
        /// - Returns: The stamps.
        func timestamps() async throws -> [Date] {
            try await stored().map(\.updatedAt)
        }
    }
}

/// Everything the fakes do, except that the Nth ``SetEntry`` save onwards refuses.
///
/// **A count rather than a flag**, which is the whole of `NFR-1.8`'s claim: a double that refused
/// every write cannot tell "the rows before it were kept" from "no row was ever attempted".
private struct SetWriteRefusingRepository: WorkoutRepository, PlannedTargetRepository {
    /// The fakes everything else delegates to.
    let wrapped: any WorkoutRepository

    /// How many set saves succeed before the rest refuse.
    let refusingFrom: Int

    /// How many have been attempted. A reference type, the repository being a value.
    let attempts = Counter()

    /// Counts the set saves, so the refusal starts at a fixed one.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        /// One more attempt.
        ///
        /// - Returns: How many there have now been, counting from zero.
        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            defer { count += 1 }
            return count
        }
    }

    func save(_ set: SetEntry) async throws {
        guard attempts.next() < refusingFrom else {
            throw RepositoryError.recordNotFound(id: set.id)
        }
        try await wrapped.save(set)
    }

    func plannedTargets(
        forEntryID entryID: UUID, includingDeleted: Bool
    ) async throws -> [PlannedTargetGroup] {
        []
    }
    func save(_ group: PlannedTargetGroup) async throws {
        throw RepositoryError.recordNotFound(id: group.id)
    }
    func sessions(
        forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(
            forProgramRunID: runID, week: week, includingDeleted: includingDeleted)
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
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws {
        try await wrapped.deleteExerciseEntry(id: id)
    }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}
