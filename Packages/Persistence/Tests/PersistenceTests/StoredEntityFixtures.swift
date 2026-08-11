import Foundation
import SwiftData
import Testing

@testable import Persistence

// Test-only entities. The conventions are proven against these rather than against a real model,
// so that T-0.31's and T-0.32's entities inherit a checked convention instead of defining it, and
// so this task adds no model to the schema, the CloudKit audit or the migration plan.

@Model
final class FixtureEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    var label: String = ""

    init(label: String = "", createdAt: Date = .now, updatedAt: Date = .now) {
        self.label = label
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class FixtureCacheEntity: CachedDerivedEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    var computationVersion: Int = 0

    init(computationVersion: Int) {
        self.computationVersion = computationVersion
    }
}

/// Serialises `ModelContainer` construction across the suite.
///
/// **Building two containers concurrently crashes the process**, measured on Swift 6.3.3 at roughly
/// 6% of parallel runs against 0 of 20 serial ones. It is a SwiftData constraint rather than
/// anything about the data: the tests hold no shared state, and each container is a separate
/// in-memory store. Serialising construction alone keeps the tests parallel and isolated.
let containerLock = NSLock()

/// An in-memory store holding the fixture entities. One container per call, so tests cannot see
/// each other's rows.
func makeFixtureContext() throws -> ModelContext {
    let schema = Schema([FixtureEntity.self, FixtureCacheEntity.self])
    return try makeContext(for: schema)
}

/// A context over `schema`, built under ``containerLock``.
func makeContext(for schema: Schema) throws -> ModelContext {
    containerLock.lock()
    defer { containerLock.unlock() }
    let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

/// Every way `T` fails the ``StoredEntity`` conventions against a real store, empty when it honours
/// them.
///
/// **Violations are returned rather than asserted so that this check is itself testable.** It is
/// what T-0.31 and T-0.32 inherit for nine entities, and a gate nobody has watched fail is
/// decoration — `ConventionsGateTests` watches it.
///
/// Conforming to the protocol only proves the four properties exist. What needs checking per entity
/// is that the defaults behave: an `id` defaulted to a single shared value, or a `deletedAt`
/// defaulted to a date, satisfies the compiler and breaks the schema.
func storedEntityConventionViolations<T: StoredEntity>(
    of make: () -> T,
    in context: ModelContext
) throws -> [String] {
    var violations: [String] = []
    let first = make()
    let second = make()

    if first.id == second.id { violations.append("id is not minted per instance") }
    if first.deletedAt != nil { violations.append("a new row is not live") }

    context.insert(first)
    context.insert(second)
    try context.save()

    let live = try context.fetch(FetchDescriptor<T>.notDeleted())
    if live.count != 2 { violations.append("live rows do not read back: \(live.count) of 2") }

    first.markDeleted()
    try context.save()

    let afterDelete = try context.fetch(FetchDescriptor<T>.notDeleted())
    if afterDelete.map(\.id) != [second.id] { violations.append("a soft-deleted row is not excluded") }

    return violations
}

// Four checks, and two more were removed after a mutation probe showed nothing could turn them red:
//
// - **"a soft-deleted row left the store"** is unreachable rather than untested. The only way a row
//   leaves is a hard delete, which `no_hard_delete_outside_purge` bans across the whole package,
//   tests included — so a broken fixture proving this check works cannot be written. That the
//   descriptor itself still returns deleted rows is covered in `SoftDeleteTests`.
// - **"isSoftDeleted disagrees with deletedAt"** was a tautology by construction. `isSoftDeleted` is
//   a protocol *extension* member, so in a generic context it statically dispatches to the extension
//   — the check compared a definition against itself. An entity may shadow it on the concrete type,
//   and this helper would never see the shadow; leaving it a non-requirement is what keeps the
//   protocol's own answer authoritative.

/// Asserts that `T` honours the ``StoredEntity`` conventions. This is what T-0.31 and T-0.32 call
/// once per entity.
func assertStoredEntityConventions<T: StoredEntity>(
    _ make: () -> T,
    in context: ModelContext,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let violations = try storedEntityConventionViolations(of: make, in: context)
    #expect(
        violations.isEmpty,
        "\(T.self) breaks the conventions: \(violations.joined(separator: "; "))",
        sourceLocation: sourceLocation
    )
}
