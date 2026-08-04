// NEGATIVE FIXTURE — must NOT trigger `no_imports_in_core`.
//
// `no_imports_in_core` is anchored at the start of a line, so an ordinary `//` comment can never
// match it: the line begins with a slash. A *block* comment can, and this file is the measurement
// rather than the assumption — removing `match_kinds` from the rule and re-linting this file
// produces a violation, verified 2026-08-04. So `match_kinds` is load-bearing here for the same
// reason it is on the other two import bans, and this fixture is what would notice if it were
// dropped as redundant.
//
// The module header in PowerliftingCore.swift and RealMath.swift's own doc comment both discuss
// imports at length, which is why the rule has to tell prose from code at all.

/*
import Darwin
import Foundation
*/

struct BlockCommentImportFixture {
    let placeholder = 0
}
