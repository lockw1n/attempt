// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings as every other package here — see the commented block in
// Packages/PowerliftingCore/Package.swift for what each one buys.
//
// NO `.defaultIsolation(MainActor.self)`, unlike the five feature packages. The whole point of this
// module is that the computation is NOT on the main actor (TR-1.5), so a default that put it there
// would have to be undone on the one type that matters. The `@Observable` state here says
// `@MainActor` on itself instead — it is one type, and being explicit about it is the cheaper half.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

// TR-1.5, TR-1.6: derived-value recomputation and PR cache invalidation.
//
// NOT A FEATURE MODULE, and the level in the tree says so. `TR-1.3` names the five feature modules
// exhaustively and four of them read this — the PR list and badge in ExerciseLibrary and Logging,
// the e1RM tiles in Dashboard, the formula picker in Settings — so it cannot live in any one of
// them, and a sixth directory under Packages/Features/ would be a feature module by the only
// definition the tree has. It sits beside SeedImport instead: above RepositoryInterface, below the
// features, named for the job it does.
//
// TWO DEPENDENCIES, and the absence of the others is the point. `PowerliftingCore` holds the two
// calculators this wraps; `RepositoryInterface` is how it reads sets and writes the cache. There is
// no `DesignSystem` and no `AppNavigation` because nothing here renders, and no `Persistence` for
// the reason no feature has one (TR-0.1.2).
//
// `platforms:` is required rather than decorative — the repository protocols are `async` and the
// state type is `@Observable`; see the trap in PowerliftingCore's manifest for what a clause-less
// manifest costs under xcodebuild.
let package = Package(
    name: "DerivedValues",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DerivedValues", targets: ["DerivedValues"])
    ],
    dependencies: [
        .package(path: "../PowerliftingCore"),
        .package(path: "../RepositoryInterface"),
        // TEST-ONLY, on the test target alone — the shape the feature manifests have. The recompute
        // is asserted against a store that was actually written to and read back, so a stub that
        // returned what a test handed it could not fail any of it.
        .package(path: "../RepositoryFakes"),
    ],
    targets: [
        .target(
            name: "DerivedValues",
            dependencies: ["PowerliftingCore", "RepositoryInterface"],
            swiftSettings: settings
        ),
        .testTarget(
            name: "DerivedValuesTests",
            dependencies: ["DerivedValues", "RepositoryFakes"],
            swiftSettings: settings
        ),
    ]
)
