// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings as every other package here — see the commented block in
// Packages/PowerliftingCore/Package.swift.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// TR-0.5.1, second half: the seed catalogue's importer — the only thing that maps the published
// payload onto stored rows.
//
// IT IS A PACKAGE BECAUSE IT IS THE ONE PLACE THAT HAS TO NAME BOTH SIDES, AND NEITHER SIDE MAY
// NAME THE OTHER. `SeedContent` depends on `PowerliftingCore` alone and must keep doing so — its
// manifest has the argument: `TR-0.5.2` serves the same document from a CDN, so a payload shaped
// like `RepositoryInterface.Exercise` would make a storage refactor a breaking change for every
// installed app. `RepositoryInterface` may not depend on `SeedContent` either; the seed is one
// consumer of the storage boundary and the boundary carries no consumer's schema. So the mapping
// lives above both, which is exactly the shape `RepositoryFakes` has for the same reason.
//
// It does NOT depend on `Persistence`, and the test target does not either — unusually for this
// repo. The importer is a *consumer* of `ExerciseRepository`, not an implementation of it, so what
// it needs is a subject to run against rather than a second subject to agree with: the shared
// conformance suite in `RepositoryFakes` is what already says the fake and the SwiftData
// implementation answer alike. A copy of these tests against `Persistence` would re-assert that.
//
// Not added to the Linux job, and not to the coverage job, for the reasons `SeedContent`'s manifest
// gives: those jobs' steps are the packages whose *requirements* name Linux and the one package
// `G-6.1` names.
//
// `platforms:` is required — the five repository protocols are `async`, which needs iOS 13, and
// Xcode builds a clause-less package target against the SDK's own floor. See the trap in
// PowerliftingCore's manifest.
let package = Package(
    name: "SeedImport",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SeedImport", targets: ["SeedImport"])
    ],
    dependencies: [
        .package(path: "../PowerliftingCore"),
        .package(path: "../RepositoryInterface"),
        .package(path: "../SeedContent"),
        .package(path: "../RepositoryFakes"),
    ],
    targets: [
        .target(
            name: "SeedImport",
            dependencies: ["PowerliftingCore", "RepositoryInterface", "SeedContent"],
            swiftSettings: strictSettings
        ),
        // G-6.3. `RepositoryFakes` is the subject every test here runs against; the dependency lives
        // on this target and only this target, so a consumer of the library links no store.
        .testTarget(
            name: "SeedImportTests",
            dependencies: ["SeedImport", "RepositoryFakes"],
            swiftSettings: strictSettings
        ),
    ]
)
