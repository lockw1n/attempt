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
//   .treatAllWarnings(as:.error) G-6.4's zero-warnings rule, enforced by the compiler rather than
//                                by review. Deliberately in the manifest and not only in CI, so a
//                                warning fails at the desk where it was written. To iterate past
//                                one locally: swift build -Xswiftc -no-warnings-as-errors.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
    .treatAllWarnings(as: .error)
]

// TR-0.1: pure Swift domain layer.
// TR-0.1.1 / NFR-0.2: this package must compile on Linux, which is the mechanical proof that
// no Apple framework has leaked in. The `dependencies` array below is empty and must stay that
// way — see docs/phase-0/tasks/T-0.02-restructure-into-packages.md.
// No `platforms:` clause on purpose. This package touches no Apple API, so it has nothing to
// gate on a platform version — and declaring a minimum would be worse than redundant: it would
// require that SDK to be present just to build, breaking the Linux job (TR-0.1.1) and pinning
// every CI runner to a specific Xcode. Consumers declare their own minimums.
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
        )
    ]
)
