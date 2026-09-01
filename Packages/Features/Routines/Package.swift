// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings as every other package here — see the commented block in
// Packages/PowerliftingCore/Package.swift for what each one buys, and Features/ExerciseLibrary's
// manifest, which is the exemplar this one follows.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
]

// TR-1.3: routines (FR-15.2). THE SIXTH FEATURE PACKAGE, and the first outside Phase 1.
//
// It sits under Packages/Features/ with the other five, which is load-bearing rather than tidy —
// `.swiftlint.yml` scopes the six G-7.7 no-raw-values rules to `Packages/Features/.*`, and the two
// scripts that walk the tree each carry a second glob for this level. ExerciseLibrary's manifest
// has the long form of both.
//
// FIVE DEPENDENCIES, the same five ExerciseLibrary has minus DerivedValues: nothing here shows a
// derived number. `ExerciseLibrary` is deliberately NOT among them — TR-1.3 forbids one feature
// module depending on another, which is why the exercise chooser this editor adds from is composed
// by the app target over `Route.exerciseLibrary(.routineExercisePicker)` rather than imported.
let package = Package(
    name: "Routines",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Routines", targets: ["Routines"])
    ],
    dependencies: [
        .package(path: "../../PowerliftingCore"),
        .package(path: "../../RepositoryInterface"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../AppNavigation"),
        .package(path: "../../Localization"),
        // TEST-ONLY, on the test target alone — the same shape ExerciseLibrary's manifest has. The
        // editor's saves are three levels of writes whose ORDER the repository enforces
        // (routine → slot → group), and a hand-written double that accepted anything could not
        // fail the test that exists to prove the order is right.
        .package(path: "../../RepositoryFakes"),
    ],
    targets: [
        .target(
            name: "Routines",
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
            name: "RoutinesTests",
            dependencies: ["Routines", "RepositoryFakes"],
            swiftSettings: settings
        ),
        // TR-1.12's references for this module's screens. A separate target for the reason
        // ExerciseLibrary's has one: every file in it is `#if os(iOS)`, because a reference is an
        // iOS rendering and `swift test` runs on macOS.
        .testTarget(
            name: "RoutinesSnapshotTests",
            dependencies: [
                "Routines",
                .product(name: "SnapshotTesting", package: "DesignSystem"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: settings
        ),
    ]
)
