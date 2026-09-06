import Foundation
import SwiftData
import Testing

@testable import Persistence

// Entities that break the conventions on purpose, so the check that nine real entities will be held
// to is proven able to fail — and to fail for the stated reason rather than merely to fail.
//
// Both breakages compile, conform, and would pass a review: an `id` default is easy to write as a
// shared constant, and a non-optional-looking `deletedAt` is a plausible "sensible default".

private enum SharedDefault {
    static let id = UUID()
}

@Model
final class SharedIDEntity: StoredEntity {
    var id: UUID = SharedDefault.id
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init() {}
}

@Model
final class BornDeletedEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = Date.now

    init() {}
}

@Suite("The conventions gate can fail")
struct ConventionsGateTests {
    private func brokenContext() throws -> ModelContext {
        try makeContext(for: Schema([SharedIDEntity.self, BornDeletedEntity.self]))
    }

    @Test("An id defaulted to a shared constant is caught, and nothing else is reported")
    func sharedIDIsCaught() throws {
        let violations = try storedEntityConventionViolations(of: { SharedIDEntity() }, in: brokenContext())

        #expect(violations == ["id is not minted per instance"])
    }

    @Test("A row born soft-deleted is caught, by three separate checks")
    func bornDeletedIsCaught() throws {
        let violations = try storedEntityConventionViolations(of: { BornDeletedEntity() }, in: brokenContext())

        #expect(violations.contains("a new row is not live"))
        #expect(violations.contains("live rows do not read back: 0 of 2"))
        #expect(violations.contains("a soft-deleted row is not excluded"))
        #expect(violations.count == 3)
    }

    @Test("A conforming entity reports nothing")
    func conformingEntityIsClean() throws {
        let violations = try storedEntityConventionViolations(of: { FixtureEntity() }, in: makeFixtureContext())

        #expect(violations.isEmpty)
    }
}

// `StoredEntity` requires these per concrete type and provides no default — see
// `StoredEntity`'s requirements for why a generic one would be the bug it guards. A fixture
// entity is a real conformance, so it owes them too; this file failing to compile is that guard
// working rather than an obstacle to route around.
extension SharedIDEntity {
    static func matchingID(_ id: UUID) -> Predicate<SharedIDEntity> {
        #Predicate<SharedIDEntity> { $0.id == id }
    }

    static var notDeleted: Predicate<SharedIDEntity> {
        #Predicate<SharedIDEntity> { $0.deletedAt == nil }
    }

    static func notDeleted(
        alsoMatching other: Predicate<SharedIDEntity>
    ) -> Predicate<SharedIDEntity> {
        #Predicate<SharedIDEntity> { entity in
            other.evaluate(entity) && entity.deletedAt == nil
        }
    }

    static func softDeleted(onOrBefore cutoff: Date) -> Predicate<SharedIDEntity> {
        #Predicate<SharedIDEntity> { entity in
            if let deletedAt = entity.deletedAt {
                return deletedAt <= cutoff
            } else {
                return false
            }
        }
    }
}

// `StoredEntity` requires these per concrete type and provides no default — see
// `StoredEntity`'s requirements for why a generic one would be the bug it guards. A fixture
// entity is a real conformance, so it owes them too; this file failing to compile is that guard
// working rather than an obstacle to route around.
extension BornDeletedEntity {
    static func matchingID(_ id: UUID) -> Predicate<BornDeletedEntity> {
        #Predicate<BornDeletedEntity> { $0.id == id }
    }

    static var notDeleted: Predicate<BornDeletedEntity> {
        #Predicate<BornDeletedEntity> { $0.deletedAt == nil }
    }

    static func notDeleted(
        alsoMatching other: Predicate<BornDeletedEntity>
    ) -> Predicate<BornDeletedEntity> {
        #Predicate<BornDeletedEntity> { entity in
            other.evaluate(entity) && entity.deletedAt == nil
        }
    }

    static func softDeleted(onOrBefore cutoff: Date) -> Predicate<BornDeletedEntity> {
        #Predicate<BornDeletedEntity> { entity in
            if let deletedAt = entity.deletedAt {
                return deletedAt <= cutoff
            } else {
                return false
            }
        }
    }
}
