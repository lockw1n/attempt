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
