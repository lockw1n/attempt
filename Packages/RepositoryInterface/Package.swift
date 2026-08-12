// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same three settings as PowerliftingCore, and for the same reasons — see the
// commented block in Packages/PowerliftingCore/Package.swift.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// TR-0.1.2 / TR-0.4.1: the storage boundary — five repository protocols and the record types their
// signatures are written in. Nothing here imports SwiftData, and nothing here may depend on
// `Persistence`; that direction is what makes `TR-0.4.3` a compiler fact rather than a review note.
//
// This package is built on Linux as well as on Darwin, and that is not incidental: the Linux job
// is the only mechanism that can check TR-0.1.2 at all. SwiftData ships in the Apple SDKs, so on
// Darwin *every* target can import it — measured — and no arrangement of targets there proves
// anything about linkage. On Linux the module does not exist. That is why this is a package rather
// than a target inside `Persistence`, whose `platforms:` clause would take it out of that job:
// `platforms:` is a package-level setting. The argument is in
// docs/phase-0/tasks/T-0.40-repository-protocols.md.
//
// The `platforms:` clause below does NOT conflict with that, and the note in PowerliftingCore's
// manifest saying such a clause "would break the Linux job" is wrong — measured 2026-08-12, both
// directions. SwiftPM on Linux parses the clause and ignores it; only `swift-tools-version` has to
// be new enough to know `.v26`. The clause is *required* here: `async` needs iOS 13, and with no
// clause Xcode builds a package target against the SDK's own floor, so every `async throws`
// requirement fails to compile in the app's build graph while `swift build` on macOS passes.
let package = Package(
    name: "RepositoryInterface",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RepositoryInterface", targets: ["RepositoryInterface"])
    ],
    dependencies: [
        .package(path: "../PowerliftingCore")
    ],
    targets: [
        .target(
            name: "RepositoryInterface",
            dependencies: ["PowerliftingCore"],
            swiftSettings: strictSettings
        ),
        // G-6.3. The suite is mostly a compile-time one: it conforms to all five protocols with a
        // stub that imports no SwiftData, which is the half of the layering claim `swift build`
        // alone cannot make — a protocol nothing satisfies proves only that it parses.
        .testTarget(
            name: "RepositoryInterfaceTests",
            dependencies: ["RepositoryInterface"],
            swiftSettings: strictSettings
        ),
    ]
)
