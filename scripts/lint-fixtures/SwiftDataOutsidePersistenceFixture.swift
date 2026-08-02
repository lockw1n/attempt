// FIXTURE — must trigger `no_swiftdata_outside_persistence` (TR-0.1.2).
//
// Deliberately NOT under a `Packages/Persistence/` path: that is the one place the rule excludes,
// so a fixture stored there would prove the opposite of what is intended.

import SwiftData

struct SwiftDataOutsidePersistenceFixture {
    let placeholder = 0
}
