import Foundation
import SwiftData
import Testing

@testable import Persistence

@Suite("Soft-delete reads")
struct SoftDeleteTests {
    private func seed(_ context: ModelContext, labels: [String]) throws -> [FixtureEntity] {
        let entities = labels.map { FixtureEntity(label: $0) }
        for entity in entities { context.insert(entity) }
        try context.save()
        return entities
    }

    // G-1.3. The unfiltered half is the point: a filter that returned two of two rows would pass
    // the first assertion while excluding nothing at all.
    @Test("The default read excludes soft-deleted rows, which are still in the store")
    func defaultReadExcludesDeleted() throws {
        let context = try makeFixtureContext()
        let entities = try seed(context, labels: ["a", "b", "c"])
        entities[1].markDeleted()
        try context.save()

        let live = try context.fetch(FetchDescriptor<FixtureEntity>.notDeleted())
        #expect(Set(live.map(\.id)) == Set([entities[0].id, entities[2].id]))
        #expect(live.count == 2)

        let everything = try context.fetch(FetchDescriptor<FixtureEntity>.includingDeleted())
        #expect(everything.count == 3)
    }

    // The composition case: a repository's own clause must not lose the soft-delete one, and the
    // soft-delete one must not lose the repository's. Four rows, one satisfying both.
    @Test("A caller's predicate is combined with the soft-delete clause, not substituted for it")
    func callerPredicateIsCombined() throws {
        let context = try makeFixtureContext()
        let entities = try seed(context, labels: ["keep", "skip", "keep", "skip"])
        entities[2].markDeleted()
        entities[3].markDeleted()
        try context.save()

        let wanted = #Predicate<FixtureEntity> { $0.label == "keep" }
        let rows = try context.fetch(FetchDescriptor<FixtureEntity>.notDeleted(matching: wanted))

        #expect(rows.map(\.id) == [entities[0].id])
        #expect(rows.count == 1)
    }

    @Test("Sorting survives the filter")
    func sortingSurvivesTheFilter() throws {
        let context = try makeFixtureContext()
        let entities = try seed(context, labels: ["c", "a", "b"])
        entities[0].markDeleted()
        try context.save()

        let sorted = try context.fetch(
            FetchDescriptor<FixtureEntity>.notDeleted(sortBy: [SortDescriptor(\.label)])
        )
        #expect(sorted.map(\.label) == ["a", "b"])
    }

    // The purge population. A live row is never in it, whatever its other timestamps say.
    @Test("The purge descriptor selects only rows deleted at or before the cutoff")
    func purgeDescriptorRespectsTheCutoff() throws {
        let context = try makeFixtureContext()
        let entities = try seed(context, labels: ["old", "recent", "live"])
        entities[0].markDeleted(at: Date(timeIntervalSince1970: 1_000))
        entities[1].markDeleted(at: Date(timeIntervalSince1970: 3_000))
        try context.save()

        let cutoff = Date(timeIntervalSince1970: 2_000)
        let purgeable = try context.fetch(FetchDescriptor<FixtureEntity>.deleted(onOrBefore: cutoff))

        #expect(purgeable.map(\.id) == [entities[0].id])
        #expect(purgeable.count == 1)
    }

    @Test("The cutoff is inclusive")
    func cutoffIsInclusive() throws {
        let context = try makeFixtureContext()
        let entities = try seed(context, labels: ["exact"])
        let cutoff = Date(timeIntervalSince1970: 2_000)
        entities[0].markDeleted(at: cutoff)
        try context.save()

        let purgeable = try context.fetch(FetchDescriptor<FixtureEntity>.deleted(onOrBefore: cutoff))
        #expect(purgeable.count == 1)
    }
}
