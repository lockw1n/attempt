// Fixture: must trigger `no_hard_delete_outside_purge` (G-1.3).
//
// Deliberately not compiled — it lives outside every package's Sources/ and Tests/. Three calls,
// because a purge is not the only way a row leaves the store: a single-model delete, a batch
// delete by predicate, and wiping the container all bypass `deletedAt` identically.

import Foundation
import SwiftData

struct HardDeleteFixture {
    func removeOne(_ model: some PersistentModel, from context: ModelContext) {
        context.delete(model)
    }

    func removeMany(from context: ModelContext) throws {
        try context.delete(model: FixtureRow.self)
    }

    func wipe(_ container: ModelContainer) throws {
        try container.deleteAllData()
    }
}

@Model
final class FixtureRow {
    var id: UUID = UUID()

    init() {}
}
