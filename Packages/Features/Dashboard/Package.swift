// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings, for the same reasons, as the other feature packages — see the
// commented block in Packages/Features/ExerciseLibrary/Package.swift.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
]

// TR-1.3: the dashboard (FR-1.9).
//
// Same shape as every feature package: four dependencies, no `Persistence`, one level deeper than
// the rest of Packages/. All of that is argued once, in
// Packages/Features/ExerciseLibrary/Package.swift.
// G-3.4 (T-1.14) adds two lines and a fifth dependency to the shape above. `defaultLocalization`
// plus `resources:` give the module its own catalogue at Sources/<Target>/Resources/en.lproj/, so
// its copy resolves against `Bundle.module` rather than the app's; `Localization` carries the key
// convention and the locale-explicit format styles. Read Localization's module doc before adding a
// string — a `.xcstrings` here is inert under `swift build`, which is the whole reason for the
// `.strings` form.
let package = Package(
    name: "Dashboard",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Dashboard", targets: ["Dashboard"])
    ],
    dependencies: [
        .package(path: "../../PowerliftingCore"),
        .package(path: "../../RepositoryInterface"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../AppNavigation"),
        .package(path: "../../Localization"),
        // THE SIXTH IS NOT A FEATURE PACKAGE and does not break TR-0.1.2, for the reason
        // ExerciseLibrary's manifest gives: `DerivedValues` sits below this level, over
        // `RepositoryInterface` alone. It is here because `FR-1.9.3`'s card and `FR-1.6.5`'s feed
        // behind it are both readings of the recompute actor's cache.
        .package(path: "../../DerivedValues"),
        // TEST-ONLY, on the test target alone — the shape every other feature manifest has.
        .package(path: "../../RepositoryFakes"),
    ],
    targets: [
        .target(
            name: "Dashboard",
            dependencies: [
                "PowerliftingCore",
                "RepositoryInterface",
                "DerivedValues",
                "DesignSystem",
                "AppNavigation",
                "Localization",
            ],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "DashboardTests",
            dependencies: ["Dashboard", "RepositoryFakes", "DerivedValues"],
            swiftSettings: settings
        ),
        // TR-1.12's references for this module's screens — the shape ExerciseLibrary's manifest
        // documents: every file `#if os(iOS)`, the images beside the target rather than declared as
        // resources, and `scripts/snapshot-tests.sh` running it on a simulator.
        .testTarget(
            name: "DashboardSnapshotTests",
            dependencies: [
                "Dashboard",
                "DerivedValues",
                .product(name: "SnapshotTesting", package: "DesignSystem"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: settings
        ),
    ]
)
