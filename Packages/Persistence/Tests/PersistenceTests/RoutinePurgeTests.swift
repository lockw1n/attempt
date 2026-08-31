import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

// TR-1.14, G-1.3 for the routine chain. Split from `StorePurgeTests` to keep that suite's body
// under the type-length gate; the seeding rationale in its header applies here unchanged.

@Suite("Store purge — routines")
struct RoutinePurgeTests {
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

    // The routine chain's own retention, which is transitive over two hops: a live target group
    // holds its slot, and that slot then holds the routine it sits in. A single-pass plan that
    // walked the tables in the wrong order would free the routine before the slot was put back,
    // which is the failure `retainReferenced`'s fixpoint exists for — so the group is the only
    // live row here and the two rows above it are both deleted.
    @Test("A live target group holds its slot, and the slot holds its routine")
    func routineChainRetainsTransitively() async throws {
        let harness = try RepositoryHarness()
        let routine = softDeleted(RoutineEntity(name: "Squat day"), at: longAgo)
        let slot = softDeleted(
            RoutineExerciseEntity(routineID: routine.id, exerciseID: UUID(), order: 0), at: longAgo)
        try harness.seed([
            routine,
            slot,
            RoutineTargetGroupEntity(
                routineExerciseID: slot.id,
                order: 0,
                targetWeightGrams: 90_000,
                targetReps: 4,
                targetSets: 4
            ),
        ])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 0)
        #expect(report.retained == 2)
        #expect(try count(RoutineEntity.self, in: harness) == 1)
        #expect(try count(RoutineExerciseEntity.self, in: harness) == 1)
    }

    // The other direction: with nothing live above them, the whole chain is free in one pass.
    // Without this the test above would pass for a plan that simply never frees a routine row.
    @Test("A wholly deleted routine chain is removed")
    func deletedRoutineChainGoesWhole() async throws {
        let harness = try RepositoryHarness()
        let routine = softDeleted(RoutineEntity(name: "Squat day"), at: longAgo)
        let slot = softDeleted(
            RoutineExerciseEntity(routineID: routine.id, exerciseID: UUID(), order: 0), at: longAgo)
        try harness.seed([
            routine,
            slot,
            softDeleted(
                RoutineTargetGroupEntity(
                    routineExerciseID: slot.id,
                    order: 0,
                    targetWeightGrams: 90_000,
                    targetReps: 4,
                    targetSets: 4
                ),
                at: longAgo
            ),
        ])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 3)
        #expect(report.retained == 0)
        #expect(try count(RoutineEntity.self, in: harness) == 0)
        #expect(try count(RoutineExerciseEntity.self, in: harness) == 0)
        #expect(try count(RoutineTargetGroupEntity.self, in: harness) == 0)
    }

}
