// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings, for the same reasons, as the other feature packages — see the
// commented block in Packages/Features/ExerciseLibrary/Package.swift.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
]

// TR-1.3: past training (FR-1.5).
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
    name: "History",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "History", targets: ["History"])
    ],
    dependencies: [
        .package(path: "../../PowerliftingCore"),
        .package(path: "../../RepositoryInterface"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../AppNavigation"),
        .package(path: "../../Localization"),
        // NOT A FEATURE PACKAGE and no breach of TR-0.1.2, for the reason Dashboard's manifest
        // gives: `DerivedValues` sits below this level, over `RepositoryInterface` alone. It is
        // here for `Tonnage` — `FR-1.5.1`'s session tonnage and `FR-1.9.5`'s week volume are one
        // definition, and it cannot live in either of the two feature modules that weigh sets.
        .package(path: "../../DerivedValues"),
        // TEST-ONLY, on the test target alone — the shape the other feature manifests have. The
        // session list's arithmetic is asserted against a store that was actually written to, so a
        // fake returning what a test handed it could not fail it.
        .package(path: "../../RepositoryFakes"),
    ],
    targets: [
        .target(
            name: "History",
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
            name: "HistoryTests",
            dependencies: ["History", "RepositoryFakes"],
            swiftSettings: settings
        ),
        // TR-1.12's references for this module's screens, in a target of its own for the reason
        // ExerciseLibrary's manifest gives: every file in it is `#if os(iOS)`, and
        // `scripts/snapshot-tests.sh` runs it on a simulator.
        .testTarget(
            name: "HistorySnapshotTests",
            dependencies: [
                "History",
                .product(name: "SnapshotTesting", package: "DesignSystem"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: settings
        ),
    ]
)
