// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings as every other package here — see the commented block in
// Packages/PowerliftingCore/Package.swift.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// TR-0.5.2: the schema and validator for the two `/content/v1` and `/config/v1` payloads that are
// not `exercises.json` — `formulas.json` and `flags.json`.
//
// A package of its own rather than a fourth SeedContent responsibility, for the same reason
// SeedContent is a package rather than a PowerliftingCore test helper: the validators need
// Foundation (`JSONDecoder`), and `no_foundation_in_core` covers PowerliftingCore's Sources AND
// Tests. It does not extend SeedContent because SeedContent's own manifest is explicit that its
// scope is `exercises.json` — the one payload with a *bundled* copy that has to be the same bytes
// as the served one. `formulas.json` and `flags.json` have no bundled counterpart: `RPETable`'s
// default chart is Swift source, and there is nothing to keep byte-identical to a bundle.
//
// The *library* depends on `PowerliftingCore` alone, for `RPETable` — same constraint as
// SeedContent, and the same reason: a public content contract must not be shaped like a storage
// record. The `GenerateRemoteContent` executable also depends on `SeedContent`, which does not
// weaken that: the executable is the publish tool for all three payloads, and validating the
// catalogue it publishes needs `SeedCatalogueValidator`. Nothing an app links picks up that edge.
//
// Not added to the Linux job, matching SeedContent: nothing here carries a Linux-specific
// requirement (`NFR-0.2` is PowerliftingCore's alone).
//
// No `platforms:` clause: nothing here is availability-gated. Add one the moment that stops being
// true, per the trap in PowerliftingCore's manifest.
let package = Package(
    name: "RemoteContent",
    products: [
        .library(name: "RemoteContent", targets: ["RemoteContent"]),
        // `scripts/generate-remote-content.sh` is the only caller (`TR-0.5.2`'s "scripted,
        // reproducible deploy"). Writes `formulas.json` and `flags.json` fresh on every run —
        // there is no committed copy for either to drift from — and validates all three published
        // payloads, the copied catalogue included, before the run is allowed to succeed.
        .executable(name: "GenerateRemoteContent", targets: ["GenerateRemoteContent"]),
    ],
    dependencies: [
        .package(path: "../PowerliftingCore"),
        .package(path: "../SeedContent"),
    ],
    targets: [
        .target(
            name: "RemoteContent",
            dependencies: ["PowerliftingCore"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "RemoteContentTests",
            dependencies: ["RemoteContent"],
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings
        ),
        .executableTarget(
            name: "GenerateRemoteContent",
            dependencies: ["RemoteContent", "PowerliftingCore", "SeedContent"],
            swiftSettings: strictSettings
        ),
    ]
)
