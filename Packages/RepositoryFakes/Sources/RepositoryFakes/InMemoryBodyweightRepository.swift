import Foundation
import RepositoryInterface

/// `BodyweightRepository` over a dictionary (`TR-0.4.2`).
struct InMemoryBodyweightRepository: BodyweightRepository, Sendable {
    let store: InMemoryRepositoryStore

    /// Entries dated within `range`, newest first.
    func entries(
        in range: ClosedRange<Date>,
        includingDeleted: Bool
    ) async throws -> [BodyweightEntry] {
        await store.allBodyweightEntries(in: range, includingDeleted: includingDeleted)
    }

    /// The entry carrying `id`, or `nil`.
    func entry(id: UUID, includingDeleted: Bool) async throws -> BodyweightEntry? {
        await store.bodyweightEntry(id: id, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the entry.
    func save(_ entry: BodyweightEntry) async throws {
        await store.saveBodyweightEntry(entry)
    }

    /// Soft-deletes the entry.
    func deleteEntry(id: UUID) async throws {
        try await store.deleteBodyweightEntry(id: id)
    }
}

extension InMemoryRepositoryStore {
    /// Entries dated within `range`, newest first.
    func allBodyweightEntries(
        in range: ClosedRange<Date>,
        includingDeleted: Bool
    ) -> [BodyweightEntry] {
        bodyweightEntries.values
            .filter { range.contains($0.date) }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically(by: { ($0.date, $0.id.uuidString) }, descending: true)
    }

    /// The entry carrying `id`, subject to the flag.
    func bodyweightEntry(id: UUID, includingDeleted: Bool) -> BodyweightEntry? {
        bodyweightEntries[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// Inserts or replaces `entry`.
    func saveBodyweightEntry(_ entry: BodyweightEntry) {
        upserted(entry, into: &bodyweightEntries, at: .now)
    }

    /// Soft-deletes the entry.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live entry
    ///   carries `id`.
    func deleteBodyweightEntry(id: UUID) throws {
        try softDelete(id: id, in: &bodyweightEntries, at: .now)
    }
}
