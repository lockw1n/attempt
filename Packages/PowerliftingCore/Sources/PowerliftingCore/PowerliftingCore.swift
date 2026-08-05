// The pure domain layer: value types, formulas and resolvers.
//
// Constraints on everything in this module:
//
// - No imports at all (NFR-0.2). Not Foundation, not SwiftUI, not SwiftData — and since T-0.14,
//   not the platform modules either. Three mechanisms enforce it and none of them overlaps
//   completely: a Linux CI job (T-0.08) rejects Apple-platform frameworks, `no_foundation_in_core`
//   catches Foundation, which compiles on Linux and so is invisible to that job, and
//   `no_imports_in_core` bans the rest — including `Darwin` and `Glibc`, which the other two let
//   through. Together they hold this directory at zero import lines, which is the property the
//   coverage matrix cites as evidence rather than any one of the three.
// - The cost of that is real and paid in RealMath.swift: `pow` and `exp` do not exist here, so
//   Lombardi's and Wathan's e1RM equations (TR-0.2.4) use hand-rolled ones, measured against the
//   system maths library before being committed. Read T-0.14's notes before reaching for an
//   import to avoid a similar cost — the decision was made once, with numbers behind it.
// - No I/O. Everything here is a pure function or a value type. Persistence lives in the
//   Persistence package, behind repository protocols (TR-0.1.2).
// - Weights are Int grams (G-1.1). No floating-point weight is ever persisted, and `Weight`
//   (T-0.10) is the only representation the rest of the module accepts.
// - Value types are Sendable (TR-0.1.3), declared explicitly: implicit synthesis does not apply
//   to `public` types, so an omitted conformance compiles here and fails at the first consumer.
// - Public API documents units and valid ranges (NFR-0.3).
//
// This file declares no types on purpose, and should keep declaring none: a type sharing its
// module's name causes Swift lookup ambiguity. It exists to carry the constraints above, which
// are otherwise recorded nowhere in the source tree.
//
// The Linux CI job's tripwire was verified against this file on 2026-08-02 (T-0.08): an
// `import CoreGraphics` here failed the `Build PowerliftingCore` step with "no such module
// 'CoreGraphics'" while all three macOS jobs stayed green. The rule above is enforced, not
// merely asserted — with one exception, `import Foundation`, which compiles on Linux and is
// caught by review only until T-0.05 adds a lint rule.
