// FIXTURE — must trigger `no_foundation_in_core` (NFR-0.2).
//
// This is the most important fixture in the directory. The Linux CI job (T-0.08) cannot catch
// `import Foundation` — Foundation ships on Linux, so it compiles and every job stays green — so
// this lint rule is the ONLY mechanical enforcement of the Foundation half of NFR-0.2. If this
// fixture stops failing, that requirement is unenforced and nothing else will say so.
//
// The `Packages/PowerliftingCore/` path segment is load-bearing: the rule is scoped to it.

import Foundation

struct FoundationFixture {
    let placeholder = 0
}
