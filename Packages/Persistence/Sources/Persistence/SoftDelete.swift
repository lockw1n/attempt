import Foundation
import SwiftData

extension FetchDescriptor where T: StoredEntity {
    /// Live rows only — the default every repository read is expected to use (`G-1.3`).
    ///
    /// Soft-deleted rows are still in the store and SwiftData filters nothing on its own, so a read
    /// that builds its own descriptor silently returns deleted history.
    static func notDeleted(sortBy: [SortDescriptor<T>] = []) -> FetchDescriptor<T> {
        FetchDescriptor<T>(predicate: #Predicate { $0.deletedAt == nil }, sortBy: sortBy)
    }

    /// Live rows also matching `predicate`.
    ///
    /// The caller's clause is combined here rather than restated, so a repository never has to
    /// remember to add `deletedAt == nil` to a query of its own.
    static func notDeleted(
        matching predicate: Predicate<T>,
        sortBy: [SortDescriptor<T>] = []
    ) -> FetchDescriptor<T> {
        let combined = #Predicate<T> { entity in
            predicate.evaluate(entity) && entity.deletedAt == nil
        }
        return FetchDescriptor<T>(predicate: combined, sortBy: sortBy)
    }

    /// Soft-deleted rows included — for a purge, an export or a diagnostic, never for display.
    ///
    /// Spelled out at the call site on purpose: reading deleted history is a deliberate act, and
    /// this is the only descriptor that permits it.
    static func includingDeleted(sortBy: [SortDescriptor<T>] = []) -> FetchDescriptor<T> {
        FetchDescriptor<T>(sortBy: sortBy)
    }

    /// Rows matching `predicate`, soft-deleted ones included — the `includingDeleted: true` half of
    /// a repository read that also filters.
    ///
    /// The pair with ``notDeleted(matching:sortBy:)`` is what lets a repository branch on the flag
    /// by choosing a descriptor rather than by composing a `deletedAt` clause of its own.
    static func includingDeleted(
        matching predicate: Predicate<T>,
        sortBy: [SortDescriptor<T>] = []
    ) -> FetchDescriptor<T> {
        FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
    }

    /// Rows soft-deleted at or before `cutoff` — the population an explicit purge may hard-delete.
    ///
    /// `G-1.3` allows `modelContext.delete(_:)` in a purge routine and nowhere else, which is why
    /// this descriptor exists rather than each caller writing the cutoff clause itself.
    static func deleted(onOrBefore cutoff: Date, sortBy: [SortDescriptor<T>] = []) -> FetchDescriptor<T> {
        FetchDescriptor<T>(
            predicate: #Predicate { entity in
                if let deletedAt = entity.deletedAt {
                    return deletedAt <= cutoff
                } else {
                    return false
                }
            },
            sortBy: sortBy
        )
    }
}
