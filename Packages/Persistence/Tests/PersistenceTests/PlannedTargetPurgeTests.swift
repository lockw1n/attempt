import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

// TR-15.3, G-1.3 for a session's planned targets. Split from `StorePurgeTests` on
// `RoutinePurgeTests`' reason — that suite's body is at the type-length gate — and the seeding
// rationale in its header applies here unchanged.

@Suite("Store purge — planned targets")
struct PlannedTargetPurgeTests {
    private let longAgo = Date(timeIntervalSince1970: 1_000_000)
    private let cutoff = Date(timeIntervalSince1970: 1_500_000)

    private func softDeleted<T: StoredEntity>(_ row: T, at when: Date) -> T {
        row.deletedAt = when
        return row
    }

    private func count<T: StoredEntity>(
        _ type: T.Type,
        in harness: RepositoryHarness
    ) throws -> Int {
        try harness.store().rows(type, includingDeleted: true).count
    }

    // The same transitivity the set edge has: a session's plan is one of its own rows, so a live
    // planned target holds the entry it was planned for and that entry holds the session. A live
    // target under a deleted entry is a foreign row rather than one this app can author — the
    // cascade takes the plan with the exercise — which is exactly why the edge needs a test of its
    // own: without one the retain clause can be deleted and every other purge assertion still
    // passes.
    @Test("A live planned target holds the entry it was planned for, and its session")
    func aLivePlannedTargetHoldsItsEntry() async throws {
        let harness = try RepositoryHarness()
        let squat = makeSquat()
        let session = softDeleted(WorkoutSessionEntity(date: longAgo), at: longAgo)
        let entry = softDeleted(
            ExerciseEntryEntity(sessionID: session.id, exerciseID: squat.id, order: 0), at: longAgo)
        let planned = PlannedTargetGroupEntity(
            exerciseEntryID: entry.id,
            order: 0,
            targetWeightGrams: 100_000,
            targetReps: 5,
            targetSets: 3
        )
        try harness.seed([squat, session, entry, planned])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 0)
        #expect(report.retained == 2)
        #expect(try count(ExerciseEntryEntity.self, in: harness) == 1)
        #expect(try count(WorkoutSessionEntity.self, in: harness) == 1)
        #expect(try count(PlannedTargetGroupEntity.self, in: harness) == 1)
    }

    // The other direction, on `RoutinePurgeTests`' argument: with nothing live above it the plan
    // goes too, so the test above cannot pass for a plan that simply never frees these rows.
    @Test("A deleted planned target under a deleted entry goes with it")
    func aDeletedPlannedTargetGoesWithItsEntry() async throws {
        let harness = try RepositoryHarness()
        let squat = makeSquat()
        let session = softDeleted(WorkoutSessionEntity(date: longAgo), at: longAgo)
        let entry = softDeleted(
            ExerciseEntryEntity(sessionID: session.id, exerciseID: squat.id, order: 0), at: longAgo)
        let planned = softDeleted(
            PlannedTargetGroupEntity(
                exerciseEntryID: entry.id,
                order: 0,
                targetWeightGrams: 100_000,
                targetReps: 5,
                targetSets: 3
            ),
            at: longAgo
        )
        try harness.seed([squat, session, entry, planned])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(try count(PlannedTargetGroupEntity.self, in: harness) == 0)
        #expect(try count(ExerciseEntryEntity.self, in: harness) == 0)
        #expect(report.retained == 0)
    }
}
