// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings as every other package here — see the commented block in
// Packages/PowerliftingCore/Package.swift.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// DOD-0.3: the throwaway harness that runs the whole stack end to end, and OUT-0.1's boundary
// around it.
//
// IT PUBLISHES NO LIBRARY PRODUCT, AND THAT IS THE EXCLUSION MECHANISM. `OUT-0.1` requires the
// harness to stay out of release builds; a package exposing only an executable product cannot be
// linked into the app target at all, so the requirement is held by the manifest rather than by a
// build configuration somebody has to keep set. `scripts/check-harness-excluded.sh` asserts that
// this stays true — that no library product appears, that `Attempt.xcodeproj` never references the
// package, and that no app source imports it.
//
// The split between the two targets is the same one `RepositoryFakes` has: `DebugHarness` names
// the storage *boundary* and knows no store, while `HarnessCommand` is the composition root that
// picks one. That is what lets the scenario be tested against both implementations rather than
// only against whichever one the executable happens to open.
//
// `platforms:` is required — the repository protocols are `async`, which needs iOS 13, and Xcode
// builds a clause-less package target against the SDK's own floor. See the trap in
// PowerliftingCore's manifest.
let package = Package(
    name: "DebugHarness",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .executable(name: "attempt-harness", targets: ["HarnessCommand"])
    ],
    dependencies: [
        .package(path: "../PowerliftingCore"),
        .package(path: "../RepositoryInterface"),
        .package(path: "../SeedImport"),
        .package(path: "../Persistence"),
        .package(path: "../RepositoryFakes"),
    ],
    targets: [
        .target(
            name: "DebugHarness",
            dependencies: ["PowerliftingCore", "RepositoryInterface", "SeedImport"],
            swiftSettings: strictSettings
        ),
        // The only target that names `Persistence`, and the only one that decides where the store
        // lives. Everything it does beyond that is printing.
        .executableTarget(
            name: "HarnessCommand",
            dependencies: ["DebugHarness", "Persistence"],
            swiftSettings: strictSettings
        ),
        // G-6.3. Both subjects, deliberately: the fakes make the scenario cheap to assert against,
        // and `Persistence` is the half that makes `DOD-0.3`'s "the whole stack runs end to end"
        // a test rather than a claim about the executable nobody runs in CI.
        .testTarget(
            name: "DebugHarnessTests",
            dependencies: ["DebugHarness", "RepositoryFakes", "RepositoryInterface", "Persistence"],
            swiftSettings: strictSettings
        ),
    ]
)
