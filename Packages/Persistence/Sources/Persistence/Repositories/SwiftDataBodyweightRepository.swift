import Foundation
import RepositoryInterface
import SwiftData

/// `BodyweightRepository` over SwiftData (`TR-0.4.2`, `FR-1.8`).
@ModelActor
actor SwiftDataBodyweightRepository: BodyweightRepository {
    func entries(in range: ClosedRange<Date>, includingDeleted: Bool) throws -> [BodyweightEntry] {
        let (start, end) = (range.lowerBound, range.upperBound)
        return try modelContext.rows(
            BodyweightEntryEntity.self,
            matching: #Predicate { $0.date >= start && $0.date <= end },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically(by: { ($0.date, $0.id.uuidString) }, descending: true)
        .map(\.record)
    }

    func entry(id: UUID, includingDeleted: Bool) throws -> BodyweightEntry? {
        try modelContext.row(BodyweightEntryEntity.self, id: id, includingDeleted: includingDeleted)?
            .record
    }

    func save(_ entry: BodyweightEntry) throws {
        try modelContext.upsert(entry, as: BodyweightEntryEntity.self)
        try modelContext.saveStamped()
    }

    func deleteEntry(id: UUID) throws {
        let entries = try modelContext.rows(
            BodyweightEntryEntity.self, id: id, includingDeleted: false)
        guard !entries.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for entry in entries { entry.markDeleted(at: now) }
        try modelContext.saveStamped(at: now)
    }
}
