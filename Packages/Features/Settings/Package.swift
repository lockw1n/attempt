// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings, for the same reasons, as the other feature packages — see the
// commented block in Packages/Features/ExerciseLibrary/Package.swift.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
]

// TR-1.3: preferences, data portability and sync (FR-1.10 – FR-1.12).
//
// Same shape as every feature package: four dependencies, no `Persistence`, one level deeper than
// the rest of Packages/. All of that is argued once, in
// Packages/Features/ExerciseLibrary/Package.swift.
//
// THE FIFTH DEPENDENCY IS TEST-ONLY, and it is the same shape `SeedImport` and `DebugHarness` have:
// `RepositoryFakes` is the subject the state tests run against, so the edge lives on the test target
// and the module itself still links the four above. The fakes' product carries `PowerliftingCore`
// and `RepositoryInterface` only — `Persistence` is a dependency of that *package*, for its own
// conformance suite, and a target that did not name it cannot import it. TR-0.1.2 is intact; what a
// hand-rolled stub here would lose is the conformance suite that says the fake behaves like the
// real store.
// G-3.4 (T-1.14) adds two lines and a fifth dependency to the shape above. `defaultLocalization`
// plus `resources:` give the module its own catalogue at Sources/<Target>/Resources/en.lproj/, so
// its copy resolves against `Bundle.module` rather than the app's; `Localization` carries the key
// convention and the locale-explicit format styles. Read Localization's module doc before adding a
// string — a `.xcstrings` here is inert under `swift build`, which is the whole reason for the
// `.strings` form.
let package = Package(
    name: "Settings",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Settings", targets: ["Settings"])
    ],
    dependencies: [
        .package(path: "../../PowerliftingCore"),
        .package(path: "../../RepositoryInterface"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../AppNavigation"),
        .package(path: "../../Localization"),
        // FR-1.7.2's picker writes a preference AND tells the recompute pipeline the estimates are
        // stale, so this module names the same edge ExerciseLibrary does: DerivedValues sits below
        // the feature level, over RepositoryInterface alone.
        .package(path: "../../DerivedValues"),
        .package(path: "../../RepositoryFakes"),
    ],
    targets: [
        .target(
            name: "Settings",
            dependencies: [
                "PowerliftingCore",
                "RepositoryInterface",
                "DesignSystem",
                "AppNavigation",
                "Localization",
                "DerivedValues",
            ],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: ["Settings", "RepositoryFakes", "DerivedValues"],
            swiftSettings: settings
        ),
        // TR-1.12's references for this module's screens. A separate target from the one above for
        // the reason the other feature packages give — every file in it is `#if os(iOS)`, and
        // `scripts/snapshot-tests.sh` runs it on a simulator. Add the suite to that script's
        // `SUITES` list or its references are compared by nothing.
        .testTarget(
            name: "SettingsSnapshotTests",
            dependencies: [
                "Settings",
                "RepositoryFakes",
                .product(name: "SnapshotTesting", package: "DesignSystem"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: settings
        ),
    ]
)
