import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

@Suite("PersonalRecordCacheEntity")
struct PersonalRecordCacheEntityTests {
    @Test("Every field survives a save and a re-read")
    func roundTrips() throws {
        let context = try makeSupportingContext()
        let exerciseID = UUID()
        let sourceSetID = UUID()
        let achieved = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(
            makeCachedRecord(
                exerciseID: exerciseID,
                repCount: 3,
                weightGrams: 180_000,
                sourceSetID: sourceSetID,
                achievedAt: achieved
            )
        )
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<PersonalRecordCacheEntity>.notDeleted()).first
        )

        #expect(stored.exerciseID == exerciseID)
        #expect(stored.repCount == 3)
        #expect(stored.weightGrams == 180_000)
        #expect(stored.sourceSetID == sourceSetID)
        #expect(stored.achievedAt == achieved)
        #expect(stored.computationVersion == 1)
    }

    // G-1.5's done-when. A bump invalidates every cached row at the old version, and the rows are
    // otherwise untouched — invalidation is a question asked of the row, not a mutation of it.
    @Test("Bumping the rules version invalidates every cached record")
    func aVersionBumpInvalidatesTheCache() throws {
        let context = try makeSupportingContext()
        let exerciseID = UUID()
        let shipped = PersonalRecordCalculator.computationVersion
        for (repCount, grams) in [(1, 200_000), (3, 180_000), (5, 160_000)] {
            context.insert(
                makeCachedRecord(exerciseID: exerciseID, repCount: repCount, weightGrams: grams)
            )
        }
        try context.saveStamped()

        let stored = try context.fetch(
            FetchDescriptor<PersonalRecordCacheEntity>.notDeleted(sortBy: [SortDescriptor(\.repCount)])
        )

        #expect(stored.map(\.repCount) == [1, 3, 5])
        #expect(stored.allSatisfy { $0.wasComputed(byRulesVersion: shipped) })
        #expect(stored.contains { $0.wasComputed(byRulesVersion: shipped + 1) } == false)
        // The rows themselves are unchanged: a bump is a question the caller asks, not a write.
        #expect(stored.map(\.weightGrams) == [200_000, 180_000, 160_000])
    }

    // Zero is reserved for "no version was recorded" — it is what G-2.5's defaulted column holds —
    // so a row nothing computed must not read as current under any real version, including the
    // first one.
    @Test("A row at the reserved zero matches no real version")
    func theReservedZeroMatchesNothing() throws {
        let context = try makeSupportingContext()
        let unversioned = makeCachedRecord(
            exerciseID: UUID(),
            repCount: 1,
            weightGrams: 200_000,
            computationVersion: 0
        )
        context.insert(unversioned)
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<PersonalRecordCacheEntity>.notDeleted()).first
        )

        #expect(stored.computationVersion == 0)
        #expect(PersonalRecordCalculator.computationVersion >= 1)
        #expect(stored.wasComputed(byRulesVersion: PersonalRecordCalculator.computationVersion) == false)
        #expect(stored.wasComputed(byRulesVersion: 1) == false)
    }

    // TR-0.2.8's definition, in the shape the schema has to allow: repCount is the N, not the reps
    // performed, so one 5-rep set holds five records at the same weight and appears on five rows.
    // Anything treating (exerciseID, sourceSetID) as unique is wrong about the definition.
    @Test("One source set legitimately holds several rows at the same weight")
    func oneSetHoldsSeveralRepMaxes() throws {
        let context = try makeSupportingContext()
        let exerciseID = UUID()
        let sourceSetID = UUID()
        for repCount in 1...5 {
            context.insert(
                makeCachedRecord(
                    exerciseID: exerciseID,
                    repCount: repCount,
                    weightGrams: 160_000,
                    sourceSetID: sourceSetID
                )
            )
        }
        try context.saveStamped()

        let stored = try context.fetch(
            FetchDescriptor<PersonalRecordCacheEntity>.notDeleted(sortBy: [SortDescriptor(\.repCount)])
        )

        #expect(stored.map(\.repCount) == [1, 2, 3, 4, 5])
        #expect(stored.map(\.sourceSetID) == Array(repeating: sourceSetID, count: 5))
        #expect(stored.map(\.weightGrams) == Array(repeating: 160_000, count: 5))
    }

    // Assisted work has an N-rep max and no e1RM at all (E1RMCalculator refuses a negative weight),
    // so a cache that could not hold a negative record would lose the only record such a set sets.
    @Test("A negative record weight is a record, not an absence")
    func assistedWorkCaches() throws {
        let context = try makeSupportingContext()
        context.insert(
            makeCachedRecord(exerciseID: UUID(), repCount: 5, weightGrams: -20_000)
        )
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<PersonalRecordCacheEntity>.notDeleted()).first
        )

        #expect(stored.weightGrams == -20_000)
    }
}
