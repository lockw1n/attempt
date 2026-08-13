// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings as every other package here — see the commented block in
// Packages/PowerliftingCore/Package.swift.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// TR-0.5.1: the seed payload's schema and its validator.
//
// IT IS A PACKAGE BECAUSE THE VALIDATOR NEEDS FOUNDATION AND THE VOCABULARIES IT CHECKS DO NOT
// LIVE IN A FOUNDATION PACKAGE. The four enums are `PowerliftingCore`'s, and that package is
// Foundation-free in `Sources/` AND `Tests/` — `no_foundation_in_core` is scoped to
// `Packages/PowerliftingCore/.*\.swift`, so a second test target inside it does not help. Measured:
// a probe file under `Packages/PowerliftingCore/Tests/` importing Foundation fails
// `swiftlint --strict`. A validator without `JSONDecoder` and `UUID` is not a validator, so the
// options were a carved exception in the only guard that package's tests have, or this.
//
// It depends on `PowerliftingCore` alone, and must keep doing so. The payload is NOT a storage
// record — `TR-0.5.2` publishes this same file to a CDN, and a public content contract that is
// shaped like `RepositoryInterface.Exercise` makes a storage refactor a breaking change for every
// installed app. Mapping a validated entry onto that record is the seed importer's job.
//
// Not added to the Linux job. It would build there — nothing here is Apple-only — but that job's
// steps are the packages whose *requirements* name Linux, and a third step would imply this one
// carries NFR-0.2 too.
//
// No `platforms:` clause: nothing here is availability-gated. Add one the moment that stops being
// true, per the trap in PowerliftingCore's manifest.
let package = Package(
    name: "SeedContent",
    products: [
        .library(name: "SeedContent", targets: ["SeedContent"])
    ],
    dependencies: [
        .package(path: "../PowerliftingCore")
    ],
    targets: [
        // TR-0.5.1. `.copy` rather than `.process`, which flattens the directory away: the payload
        // has to stay at `Resources/exercises.json` inside the bundle, because that is where
        // `BundledCatalogue` looks for it. Measured — `.process` puts it at the bundle root and
        // every call throws `PayloadMissing`.
        .target(
            name: "SeedContent",
            dependencies: ["PowerliftingCore"],
            resources: [.copy("Resources")],
            swiftSettings: strictSettings
        ),
        // G-6.3. The fixtures are files rather than strings built in Swift, because the failure
        // modes this validator exists to catch are failures of an authored *file* — a payload
        // constructed through the initialisers cannot express a malformed UUID or a misspelled key.
        .testTarget(
            name: "SeedContentTests",
            dependencies: ["SeedContent"],
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings
        ),
    ]
)
