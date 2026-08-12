// swift-tools-version: 6.2
// (6.2 is the minimum that knows about `.v26`; see the iOS 26 decision in
//  docs/phase-0/open-questions.md → Q-0.1. CI images must be Swift 6.2+.)

import PackageDescription

// G-6.4 (T-0.06). Applied to every target in this package, production and test alike.
//
//   .swiftLanguageMode(.v6)      Swift 6 language mode. Redundant under tools-version 6.2, where
//                                v6 is already the default — stated anyway so that lowering the
//                                tools version, or a future default change, cannot silently
//                                downgrade strict concurrency. Complete concurrency checking is
//                                what v6 *is*; there is no separate flag to set, and no way to
//                                ask for less than complete from inside the mode.
//
//   .defaultIsolation(nil)       Actor-agnostic by default: declarations are `nonisolated` unless
//                                they say otherwise. This is SwiftPM's default too, but it is the
//                                opposite of the app target's SWIFT_DEFAULT_ACTOR_ISOLATION =
//                                MainActor, and TR-0.1.3's Sendable value types must not acquire
//                                an implicit @MainActor from whatever builds them. Verified to
//                                have teeth: flipping it to .defaultIsolation(MainActor.self)
//                                makes nonisolated access to a plain class property an error.
//
// G-6.4's zero-warnings rule is NOT here. `.treatAllWarnings(as: .error)` used to be, and was
// removed in T-0.03 (2026-08-02) because it makes the app unbuildable from Xcode: Xcode injects
// `-suppress-warnings` into package targets it builds as dependencies, and the compiler rejects
// that together with `-warnings-as-errors`. Do not add it back without reading
// scripts/swift-strict-flags.sh, which explains what was tried and where the gate lives now
// (`scripts/build-packages.sh`, with `scripts/verify-warnings-gate.sh` proving it still fires).
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// TR-0.1: pure Swift domain layer.
// TR-0.1.1 / NFR-0.2: this package must compile on Linux, which is the mechanical proof that
// no Apple framework has leaked in. The `dependencies` array below is empty and must stay that
// way — see docs/phase-0/tasks/T-0.02-restructure-into-packages.md.
// No `platforms:` clause on purpose: this package touches no Apple API and uses nothing carrying
// an availability annotation, so it has nothing to gate on a platform version. Consumers declare
// their own minimums.
//
// It is NOT because a clause would break the Linux job — that claim used to be here and is false,
// measured 2026-08-12 in both directions: SwiftPM on Linux parses `platforms:` and ignores it.
// What a missing clause actually costs is availability-gated API, which is why RepositoryInterface
// declares one (T-0.40): its `async` requirements need iOS 13, and Xcode builds a clause-less
// package target against the SDK's own floor. If this package ever needs `Identifiable`, an actor
// or anything `@available`-annotated, add the clause — the Linux job will not notice.
let package = Package(
    name: "PowerliftingCore",
    products: [
        .library(name: "PowerliftingCore", targets: ["PowerliftingCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PowerliftingCore",
            swiftSettings: strictSettings
        ),
        // G-6.1 / G-6.3: the suite whose line coverage the 90% gate measures (T-0.61).
        // Swift Testing, not XCTest — it ships with the toolchain, so this adds no package
        // dependency and keeps the empty `dependencies` array above intact (TR-0.1.1).
        .testTarget(
            name: "PowerliftingCoreTests",
            dependencies: ["PowerliftingCore"],
            swiftSettings: strictSettings
        ),
    ]
)
