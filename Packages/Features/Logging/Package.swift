// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings, for the same reasons, as the other feature packages — see the
// commented block in Packages/Features/ExerciseLibrary/Package.swift.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
]

// TR-1.3: workout logging (FR-1.2).
//
// Same shape as every feature package: four dependencies, no `Persistence`, one level deeper than
// the rest of Packages/. All of that is argued once, in
// Packages/Features/ExerciseLibrary/Package.swift.
// THE FIFTH DEPENDENCY IS TEST-ONLY — `RepositoryFakes`, on the test target alone. Why that keeps
// TR-0.1.2 intact is argued once, in Packages/Features/Settings/Package.swift.
// G-3.4 (T-1.14) adds two lines and a fifth dependency to the shape above. `defaultLocalization`
// plus `resources:` give the module its own catalogue at Sources/<Target>/Resources/en.lproj/, so
// its copy resolves against `Bundle.module` rather than the app's; `Localization` carries the key
// convention and the locale-explicit format styles. Read Localization's module doc before adding a
// string — a `.xcstrings` here is inert under `swift build`, which is the whole reason for the
// `.strings` form.
let package = Package(
    name: "Logging",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Logging", targets: ["Logging"])
    ],
    dependencies: [
        .package(path: "../../PowerliftingCore"),
        .package(path: "../../RepositoryInterface"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../AppNavigation"),
        .package(path: "../../Localization"),
        .package(path: "../../RepositoryFakes"),
    ],
    targets: [
        .target(
            name: "Logging",
            dependencies: [
                "PowerliftingCore",
                "RepositoryInterface",
                "DesignSystem",
                "AppNavigation",
                "Localization",
            ],
            resources: [.process("Resources")],
            swiftSettings: settings
        ),
        .testTarget(
            name: "LoggingTests",
            dependencies: ["Logging", "RepositoryFakes"],
            swiftSettings: settings
        ),
        // TR-1.12's references for this module's screens. A separate target from the one above for
        // the reason ExerciseLibrary's manifest gives — every file in it is `#if os(iOS)`, and
        // `scripts/snapshot-tests.sh` runs it on a simulator. Add the suite to that script's
        // `SUITES` list or its references are compared by nothing.
        .testTarget(
            name: "LoggingSnapshotTests",
            dependencies: [
                "Logging",
                "RepositoryFakes",
                .product(name: "SnapshotTesting", package: "DesignSystem"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: settings
        ),
    ]
)
