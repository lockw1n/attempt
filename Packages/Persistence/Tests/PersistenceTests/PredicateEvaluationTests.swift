import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// FR-18.8.3's second clause re-applies a caller's `#Predicate` to a winner *in memory*, through
// `Predicate.evaluate(_:)`, where the store applied the same predicate in SQL. The rule is only as
// good as those two agreeing, so each column kind the module filters on is measured here: the
// rows the store answers for a predicate are exactly the rows `evaluate` accepts.
//
// Every fixture holds rows on both sides of the predicate, and each test requires that the
// store's answer is neither empty nor the whole table — otherwise a predicate that evaluates to a
// constant would agree with the store by accident.

@Suite("Predicate.evaluate agrees with the store")
struct PredicateEvaluationTests {
    /// The store's match set and the in-memory one, as id sets, with the store's shown to
    /// discriminate.
    private func compare<T: StoredEntity>(
        _ type: T.Type, in harness: RepositoryHarness, predicate: Predicate<T>
    ) throws -> (store: Set<UUID>, memory: Set<UUID>) {
        let context = harness.store()
        let every = try context.fetch(FetchDescriptor<T>.includingDeleted())
        let store = try context.fetch(FetchDescriptor<T>.includingDeleted(matching: predicate))
        try #require(!store.isEmpty && store.count < every.count)
        let memory = try every.filter { try predicate.evaluate($0) }
        return (Set(store.map(\.id)), Set(memory.map(\.id)))
    }

    @Test("An optional Date compared with nil")
    func optionalDateIsNil() throws {
        let harness = try RepositoryHarness()
        let program = UUID()
        try harness.seed([
            twin(
                programRunRecord(programID: program, endedAt: nil),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
            twin(
                programRunRecord(programID: program, endedAt: fixtureUpdatedAt),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
            twin(
                programRunRecord(programID: program, endedAt: nil),
                as: ProgramRunEntity.self,
                updatedAt: twinNewer),
        ])

        let sides = try compare(
            ProgramRunEntity.self,
            in: harness,
            predicate: #Predicate { $0.endedAt == nil })
        #expect(sides.store == sides.memory)
        #expect(sides.store.count == 2)
    }

    @Test("A Date range, both bounds inclusive")
    func dateRange() throws {
        let harness = try RepositoryHarness()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start + 7 * 86_400
        try harness.seed([
            twin(sessionRecord(date: start - 1), as: WorkoutSessionEntity.self, updatedAt: twinOlder),
            twin(sessionRecord(date: start), as: WorkoutSessionEntity.self, updatedAt: twinOlder),
            twin(sessionRecord(date: end), as: WorkoutSessionEntity.self, updatedAt: twinOlder),
            twin(sessionRecord(date: end + 1), as: WorkoutSessionEntity.self, updatedAt: twinOlder),
        ])

        let sides = try compare(
            WorkoutSessionEntity.self,
            in: harness,
            predicate: #Predicate { $0.date >= start && $0.date <= end })
        #expect(sides.store == sides.memory)
        #expect(sides.store.count == 2)
    }

    @Test("A Bool column")
    func boolColumn() throws {
        let harness = try RepositoryHarness()
        try harness.seed([
            twin(profileRecord(name: "a", isDefault: true), as: EquipmentProfileEntity.self, updatedAt: twinOlder),
            twin(profileRecord(name: "b", isDefault: false), as: EquipmentProfileEntity.self, updatedAt: twinOlder),
            twin(profileRecord(name: "c", isDefault: true), as: EquipmentProfileEntity.self, updatedAt: twinOlder),
        ])

        let sides = try compare(
            EquipmentProfileEntity.self,
            in: harness,
            predicate: #Predicate { $0.isDefault })
        #expect(sides.store == sides.memory)
        #expect(sides.store.count == 2)
    }

    @Test("A UUID join column compared for equality")
    func uuidEquality() throws {
        let harness = try RepositoryHarness()
        let session = UUID()
        let other = UUID()
        let exercise = UUID()
        try harness.seed([
            twin(
                entryRecord(sessionID: session, exerciseID: exercise, order: 0),
                as: ExerciseEntryEntity.self,
                updatedAt: twinOlder),
            twin(
                entryRecord(sessionID: other, exerciseID: exercise, order: 0),
                as: ExerciseEntryEntity.self,
                updatedAt: twinOlder),
            twin(
                entryRecord(sessionID: session, exerciseID: exercise, order: 1),
                as: ExerciseEntryEntity.self,
                updatedAt: twinOlder),
        ])

        let sides = try compare(
            ExerciseEntryEntity.self,
            in: harness,
            predicate: #Predicate { $0.sessionID == session })
        #expect(sides.store == sides.memory)
        #expect(sides.store.count == 2)
    }

    @Test("A UUID equality joined with a Date bound")
    func uuidAndDateBound() throws {
        let harness = try RepositoryHarness()
        let exercise = UUID()
        let other = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try harness.seed([
            twin(
                trainingMaxRecord(exerciseID: exercise, effectiveFrom: date - 86_400),
                as: TrainingMaxConfigEntity.self,
                updatedAt: twinOlder),
            twin(
                trainingMaxRecord(exerciseID: exercise, effectiveFrom: date),
                as: TrainingMaxConfigEntity.self,
                updatedAt: twinOlder),
            twin(
                trainingMaxRecord(exerciseID: exercise, effectiveFrom: date + 1),
                as: TrainingMaxConfigEntity.self,
                updatedAt: twinOlder),
            twin(
                trainingMaxRecord(exerciseID: other, effectiveFrom: date - 86_400),
                as: TrainingMaxConfigEntity.self,
                updatedAt: twinOlder),
        ])

        let sides = try compare(
            TrainingMaxConfigEntity.self,
            in: harness,
            predicate: #Predicate { $0.exerciseID == exercise && $0.effectiveFrom <= date })
        #expect(sides.store == sides.memory)
        #expect(sides.store.count == 2)
    }

    @Test("A set of ids, which is what the second fetch itself is built on")
    func setContains() throws {
        let harness = try RepositoryHarness()
        let wanted = UUID()
        let alsoWanted = UUID()
        try harness.seed([
            twin(sessionRecord(id: wanted), as: WorkoutSessionEntity.self, updatedAt: twinOlder),
            twin(sessionRecord(id: alsoWanted), as: WorkoutSessionEntity.self, updatedAt: twinOlder),
            twin(sessionRecord(), as: WorkoutSessionEntity.self, updatedAt: twinOlder),
        ])

        let sides = try compare(
            WorkoutSessionEntity.self,
            in: harness,
            predicate: WorkoutSessionEntity.matchingIDs([wanted, alsoWanted]))
        #expect(sides.store == sides.memory)
        #expect(sides.store == [wanted, alsoWanted])
    }
}
