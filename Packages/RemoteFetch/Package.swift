// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings as every other package here — see the commented block in
// Packages/PowerliftingCore/Package.swift.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// TR-0.5.3: the fetcher for the three payloads `TR-0.5.2` publishes — the launch-time freshness
// check, the on-disk cache, and the fall back to what this build ships.
//
// IT IS A PACKAGE BECAUSE IT IS THE ONE PLACE THAT NAMES BOTH CONTENT PACKAGES. `RemoteContent`'s
// *library* depends on `PowerliftingCore` alone and its manifest is explicit that nothing an app
// links may pick up a `SeedContent` edge — but the bundled leg of the fallback chain for
// `exercises.json` is `BundledCatalogue`, so the fetcher needs both sides. Same shape, and the same
// reason, as `SeedImport` sitting above `SeedContent` and `RepositoryInterface`.
//
// It does NOT depend on `SeedImport`, and must not: this layer produces bytes and knows nothing
// about storage, which is what `no_networking_in_seed_import` enforces from the other direction.
//
// Not added to the Linux job, and not to the coverage job, for the reasons `SeedContent`'s manifest
// gives: those jobs' steps are the packages whose *requirements* name Linux and the one package
// `G-6.1` names.
//
// `platforms:` is required — the fetch is `async`, which needs iOS 13, and Xcode builds a
// clause-less package target against the SDK's own floor. See the trap in PowerliftingCore's
// manifest.
let package = Package(
    name: "RemoteFetch",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RemoteFetch", targets: ["RemoteFetch"])
    ],
    dependencies: [
        .package(path: "../PowerliftingCore"),
        .package(path: "../RemoteContent"),
        .package(path: "../SeedContent"),
    ],
    targets: [
        .target(
            name: "RemoteFetch",
            dependencies: ["RemoteContent", "SeedContent"],
            swiftSettings: strictSettings
        ),
        // `PowerliftingCore` is on the test target alone: the suite builds `RemoteFormulas` values
        // at chosen revisions, which means naming `RPETable`. The library needs no such edge.
        .testTarget(
            name: "RemoteFetchTests",
            dependencies: ["RemoteFetch", "PowerliftingCore", "RemoteContent", "SeedContent"],
            swiftSettings: strictSettings
        ),
    ]
)
