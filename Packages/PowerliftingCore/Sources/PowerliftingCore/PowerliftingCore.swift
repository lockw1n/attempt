// The pure domain layer: value types, formulas and resolvers.
//
// Constraints on everything in this module:
//
// - No Apple framework imports (NFR-0.2). Not Foundation, not SwiftUI, not SwiftData.
//   A Linux CI job (T-0.08) enforces this, because a review convention will not.
// - No I/O. Everything here is a pure function or a value type. Persistence lives in the
//   Persistence package, behind repository protocols (TR-0.1.2).
// - Weights are Int grams (G-1.1). No floating-point weight is ever persisted, and the Weight
//   type (T-0.10) is the only representation the rest of the module accepts.
// - Value types are Sendable (TR-0.1.3).
// - Public API documents units and valid ranges (NFR-0.3).
//
// This file exists because SwiftPM requires at least one source file per target. It declares no
// types deliberately: a type sharing its module's name causes Swift lookup ambiguity, and any
// API added before a requirement calls for it is a guess. Delete this file once T-0.10 lands
// the Weight type.

// ┌───────────────────────────────────────────────────────────────────────────────────────────┐
// │  TEMPORARY — DO NOT MERGE.  T-0.08 negative test for NFR-0.2.                              │
// │                                                                                           │
// │  This deliberately violates the no-Apple-framework rule above, to prove the `linux` CI     │
// │  job actually goes red rather than merely being green. Expected result:                    │
// │                                                                                           │
// │      Linux core build → FAILS at the "Build PowerliftingCore" step                         │
// │                         ("no such module 'CoreGraphics'")                                  │
// │      Build / Package tests / SwiftLint → all still GREEN                                   │
// │                                                                                           │
// │  That asymmetry is the whole point: it shows the Linux job catches something no macOS      │
// │  job does. If the macOS jobs go red too, the probe is wrong — not the tripwire.            │
// │                                                                                           │
// │  Revert this block once the run is observed, then tick "done when" #2 in                   │
// │  docs/phase-0/tasks/T-0.08-ci-linux-build.md.                                              │
// └───────────────────────────────────────────────────────────────────────────────────────────┘
import CoreGraphics

public let _probe: CGFloat = 0
