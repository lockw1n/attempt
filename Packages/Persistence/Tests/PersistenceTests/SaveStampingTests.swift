import Foundation
import SwiftData
import Testing

@testable import Persistence

@Suite("Timestamp stamping on save")
struct SaveStampingTests {
    private let stamp = Date(timeIntervalSince1970: 5_000)

    @Test("An inserted row is stamped, and keeps its own createdAt")
    func insertIsStamped() throws {
        let context = try makeFixtureContext()
        let entity = FixtureEntity(createdAt: .distantPast, updatedAt: .distantPast)
        context.insert(entity)

        try context.saveStamped(at: stamp)

        #expect(entity.updatedAt == stamp)
        #expect(entity.createdAt == .distantPast)
    }

    @Test("A mutated row is stamped on the next save")
    func mutationIsStamped() throws {
        let context = try makeFixtureContext()
        let entity = FixtureEntity(updatedAt: .distantPast)
        context.insert(entity)
        try context.save()
        #expect(entity.updatedAt == .distantPast)

        entity.label = "changed"
        try context.saveStamped(at: stamp)

        #expect(entity.updatedAt == stamp)
    }

    // The stamp follows the transaction, not the table: a row nobody touched keeps the timestamp
    // it had, or G-2.4 would resolve every conflict in favour of whichever device saved last for
    // any reason at all.
    @Test("An untouched row is left alone")
    func untouchedRowIsNotStamped() throws {
        let context = try makeFixtureContext()
        let untouched = FixtureEntity(label: "quiet", updatedAt: .distantPast)
        context.insert(untouched)
        try context.saveStamped(at: Date(timeIntervalSince1970: 1_000))

        let other = FixtureEntity(label: "busy")
        context.insert(other)
        try context.saveStamped(at: stamp)

        #expect(untouched.updatedAt == Date(timeIntervalSince1970: 1_000))
        #expect(other.updatedAt == stamp)
    }

    @Test("A soft delete is a write, so it is stamped like one")
    func softDeleteIsStamped() throws {
        let context = try makeFixtureContext()
        let entity = FixtureEntity(updatedAt: .distantPast)
        context.insert(entity)
        try context.save()

        entity.markDeleted(at: Date(timeIntervalSince1970: 4_000))
        try context.saveStamped(at: stamp)

        #expect(entity.deletedAt == Date(timeIntervalSince1970: 4_000))
        #expect(entity.updatedAt == stamp)
    }

    @Test("Stamping reaches every entity in one transaction")
    func stampingReachesEveryEntity() throws {
        let context = try makeFixtureContext()
        let entity = FixtureEntity(updatedAt: .distantPast)
        let cache = FixtureCacheEntity(computationVersion: 1)
        cache.updatedAt = .distantPast
        context.insert(entity)
        context.insert(cache)

        try context.saveStamped(at: stamp)

        #expect(entity.updatedAt == stamp)
        #expect(cache.updatedAt == stamp)
    }
}
