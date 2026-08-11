// Fixture: must trigger `no_bare_save_in_persistence` (G-1.2, G-2.4).
//
// Deliberately not compiled. Two spellings, because the failure is the same either way: a
// repository calling save() on a context it holds, and a helper calling it on self from inside an
// extension — the second has no receiver to grep for.

import Foundation
import SwiftData

struct BareSaveFixture {
    func write(_ context: ModelContext) throws {
        try context.save()
    }
}

extension ModelContext {
    func writeWithoutStamping() throws {
        try save()
    }
}
