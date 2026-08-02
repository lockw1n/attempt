// The pure domain layer: value types, formulas and resolvers.
//
// Constraints on everything in this module:
//
// - No Apple framework imports (NFR-0.2). Not Foundation, not SwiftUI, not SwiftData.
//   A Linux CI job (T-0.08) enforces this, because a review convention will not.
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
