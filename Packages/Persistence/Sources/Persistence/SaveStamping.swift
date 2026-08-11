import Foundation
import SwiftData

extension ModelContext {
    /// Saves, stamping `updatedAt` on every ``StoredEntity`` this transaction inserted or changed.
    ///
    /// **This is the only save a repository may call** (`G-1.2`, `G-2.4`). Stamping at the save
    /// rather than at each mutation is what makes "every write updates `updatedAt`" structural: a
    /// mutation cannot reach the store without passing through here, so there is no call site left
    /// to forget. A bare `save()` writes a row whose `updatedAt` describes the write before it,
    /// which is a conflict resolved the wrong way once sync is on.
    ///
    /// `createdAt` is deliberately left alone — an inserted row already carries its own, and
    /// overwriting it would relabel imported or seeded history as new.
    func saveStamped(at now: Date = .now) throws {
        for model in insertedModelsArray + changedModelsArray {
            guard let entity = model as? any StoredEntity else { continue }
            entity.updatedAt = now
        }
        try save()
    }
}
