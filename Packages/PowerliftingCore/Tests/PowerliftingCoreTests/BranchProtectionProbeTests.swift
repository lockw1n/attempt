import Testing

@testable import PowerliftingCore

// ┌───────────────────────────────────────────────────────────────────────────────────────────┐
// │  TEMPORARY — DO NOT MERGE.  T-0.07 branch-protection probe (G-6.3).                        │
// │                                                                                            │
// │  Branch protection being *configured* and branch protection *blocking a merge* are two     │
// │  different claims. T-0.07's first "done when" is the second one, so it needs observing     │
// │  rather than asserting. Expected result on the PR:                                         │
// │                                                                                            │
// │      Package tests   → FAILS on the assertion below                                        │
// │      Linux core build → ALSO fails (it runs this same suite)                               │
// │      Build / SwiftLint → GREEN                                                             │
// │      The merge button → BLOCKED, naming the failed required check                          │
// │                                                                                            │
// │  The last row is the whole point. A red run that still offers a merge button means the     │
// │  protection rule is not doing what the settings page claims.                                │
// │                                                                                            │
// │  This file is deliberately lint-clean and format-clean, so the ONLY thing failing is the   │
// │  test — a probe that also trips SwiftLint would not tell you what you came to find out.    │
// │                                                                                            │
// │  Delete this file once the block is observed, then tick "done when" #1 in                  │
// │  docs/phase-0/tasks/T-0.07-ci-build-test-lint.md.                                          │
// └───────────────────────────────────────────────────────────────────────────────────────────┘
@Suite("TEMPORARY — branch-protection probe")
struct BranchProtectionProbeTests {
    @Test("Deliberately fails, to prove a red PR cannot be merged")
    func deliberatelyFailsToProveTheMergeIsBlocked() {
        #expect(Weight(grams: 1) == Weight(grams: 2))
    }
}
