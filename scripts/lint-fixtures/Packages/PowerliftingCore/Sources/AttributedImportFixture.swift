// FIXTURE — must trigger BOTH `no_imports_in_core` and `no_foundation_in_core` (NFR-0.2).
//
// This is a regression fixture for a hole found reviewing T-0.14, and it is the reason all three
// import rules stopped being anchored to the start of a line.
//
// Every import ban in this config used to begin `^[ \t]*import`, which an *attributed* import does
// not match — the line starts with `@`. Measured 2026-08-04: `@_exported import Foundation` inside
// `PowerliftingCore/Sources/` compiled, passed `swiftlint --strict` against all three rules, and
// would have passed the Linux job too, because Foundation compiles on Linux. That is precisely the
// green-CI-with-a-violated-requirement failure mode `no_imports_in_core` was added to close, so the
// rule shipped with the same hole it was written to fix.
//
// The fix was to drop the line anchor and match `\bimport[ \t]+…` anywhere, leaving `match_kinds`
// to separate code from prose. That makes `match_kinds` load-bearing for all three rules rather
// than merely defensive — see BlockCommentImportFixture.swift, which guards that direction.

@_exported import Foundation
@preconcurrency import Darwin

struct AttributedImportFixture {
    let placeholder = 0
}
