import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// Split from `RecordMappingTests.swift` to keep it under the file-length gate — the three routine
// entities' half of the same round-trip claim `RecordMappingRoundTripTests`'s header states.

@Suite("Entity ↔ record round trip — routines")
struct RoutineRecordMappingRoundTripTests {
    @Test("A routine round-trips through a record")
    func routineRoundTrips() throws {
        let context = try makeRoutineContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceRoutine(id: id),
            target: mappingTargetRoutine(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    @Test("A routine exercise slot round-trips through a record")
    func routineExerciseRoundTrips() throws {
        let context = try makeRoutineContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceRoutineExercise(id: id),
            target: mappingTargetRoutineExercise(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    @Test("A routine target group round-trips through a record")
    func targetGroupRoundTrips() throws {
        let context = try makeRoutineContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceTargetGroup(id: id),
            target: mappingTargetTargetGroup(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    // FR-15.2.2. The blank target has to survive both directions of the mapping as an ABSENCE:
    // a `nil` that came back as zero would re-open the editor on a plan to lift nothing, and a
    // zero that came back as `nil` would lose a load the lifter entered.
    @Test("A blank target weight round-trips as an absence, and a zero one as a zero")
    func blankTargetWeightRoundTrips() {
        let blank = RoutineTargetGroupEntity(
            id: UUID(),
            routineExerciseID: UUID(),
            order: 0,
            targetWeightGrams: nil,
            targetReps: 5,
            targetSets: 5)
        #expect(blank.record.targetWeight == nil)
        #expect(blank.record.prescription == nil)

        let zero = RoutineTargetGroupEntity(
            id: UUID(),
            routineExerciseID: UUID(),
            order: 0,
            targetWeightGrams: 0,
            targetReps: 5,
            targetSets: 5)
        #expect(zero.record.targetWeight == Weight(grams: 0))
        #expect(zero.record.prescription == .fixedWeight(Weight(grams: 0)))

        #expect(RoutineTargetGroupEntity(record: blank.record).targetWeightGrams == nil)
        #expect(RoutineTargetGroupEntity(record: zero.record).targetWeightGrams == 0)
    }

    @Test("A new row built from a live routine record reads back as that record")
    func insertingARecordReproducesIt() {
        assertInsertReproduces(
            mappingSourceRoutine(id: UUID()),
            insert: RoutineEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceRoutineExercise(id: UUID()),
            insert: RoutineExerciseEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceTargetGroup(id: UUID()),
            insert: RoutineTargetGroupEntity.init(record:),
            read: \.record)
    }
}
