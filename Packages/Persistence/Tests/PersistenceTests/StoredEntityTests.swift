import Foundation
import SwiftData
import Testing

@testable import Persistence

@Suite("Entity conventions")
struct StoredEntityTests {
    @Test("The fixture entity honours every convention against a real store")
    func fixtureHonoursConventions() throws {
        let context = try makeFixtureContext()
        try assertStoredEntityConventions({ FixtureEntity() }, in: context)
    }

    @Test("A cached-derived entity honours them too")
    func cacheEntityHonoursConventions() throws {
        let context = try makeFixtureContext()
        try assertStoredEntityConventions({ FixtureCacheEntity(computationVersion: 1) }, in: context)
    }

    // G-1.2: the default mints identity per instance. A default evaluated once — the failure mode
    // a schema-level default has — would give every row the same id and no unique constraint
    // (G-2.5) would notice.
    @Test("Every instance is minted a distinct id")
    func idsAreDistinct() {
        let ids = Set((0..<100).map { _ in FixtureEntity().id })
        #expect(ids.count == 100)
    }

    // The identity SwiftUI and every join sees is the client-generated UUID, not the store's
    // PersistentIdentifier: the stored property witnesses Identifiable, so PersistentModel's
    // default implementation never applies. A model whose `id` came out as a PersistentIdentifier
    // would be store-local and unstable across devices, which is what G-1.2 exists to prevent.
    @Test("Identifiable resolves to the client-generated id, concretely and erased")
    func identityIsTheClientGeneratedID() {
        let entity = FixtureEntity()
        #expect(FixtureEntity.ID.self == UUID.self)

        let erased: any PersistentModel = entity
        #expect(erased.id as? UUID == entity.id)
    }

    // G-2.5 forbids the unique constraint, so the store does not enforce identity and two rows
    // sharing an id are representable — a sync or a re-import can produce them. Pinned because it
    // is the surprising half of G-1.2's reading, and because adding @Attribute(.unique) later would
    // otherwise break CloudKit compatibility silently until T-0.33 audits it.
    @Test("The store accepts two rows sharing an id, and returns both")
    func duplicateIdsAreRepresentable() throws {
        let context = try makeFixtureContext()
        let shared = UUID()
        let first = FixtureEntity(label: "a")
        let second = FixtureEntity(label: "b")
        first.id = shared
        second.id = shared
        context.insert(first)
        context.insert(second)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<FixtureEntity>.notDeleted())

        #expect(rows.count == 2)
        #expect(Set(rows.map(\.label)) == ["a", "b"])
        #expect(Set(rows.map(\.id)) == [shared])
    }

    @Test("A new row is live, and carries both timestamps")
    func newRowIsLive() {
        let entity = FixtureEntity(createdAt: .distantPast, updatedAt: .distantPast)
        #expect(entity.deletedAt == nil)
        #expect(entity.isSoftDeleted == false)
        #expect(entity.createdAt == .distantPast)
        #expect(entity.updatedAt == .distantPast)
    }

    @Test("markDeleted stamps both deletedAt and updatedAt")
    func markDeletedStampsBoth() {
        let entity = FixtureEntity(updatedAt: .distantPast)
        let deletion = Date(timeIntervalSince1970: 1_000)

        entity.markDeleted(at: deletion)

        #expect(entity.deletedAt == deletion)
        #expect(entity.updatedAt == deletion)
        #expect(entity.isSoftDeleted)
    }

    // Re-deleting must not relabel when the row left the user's history — G-2.4 makes updatedAt
    // the conflict key, so it does advance, and the two fields deliberately diverge here.
    @Test("Re-deleting keeps the original deletedAt and advances updatedAt")
    func reDeletingKeepsTheOriginalTime() {
        let entity = FixtureEntity()
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)

        entity.markDeleted(at: first)
        entity.markDeleted(at: second)

        #expect(entity.deletedAt == first)
        #expect(entity.updatedAt == second)
    }
}
