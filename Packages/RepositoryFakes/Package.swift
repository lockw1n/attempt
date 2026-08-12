// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same three settings as PowerliftingCore, and for the same reasons — see the
// commented block in Packages/PowerliftingCore/Package.swift.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// TR-0.4.2, second half: in-memory fakes for the five repository protocols, and the conformance
// suite both they and the SwiftData implementations must pass.
//
// THE DEPENDENCY EDGES ARE THE WHOLE REASON THIS IS A PACKAGE RATHER THAN A TARGET SOMEWHERE.
// The library depends on `RepositoryInterface` alone, so a consumer wiring a fake into a preview
// pulls in no store. The TEST target additionally depends on `Persistence`, because a suite that
// runs against both implementations must be able to name both — and `RepositoryInterface` may
// never depend on `Persistence`, which rules out its test target as a home. SwiftPM keeps the two
// edges apart: `Persistence` is not linked into the library product.
//
// The library must not import SwiftData, and nothing here is trusted to remember that:
// `no_swiftdata_outside_persistence` exempts `Packages/Persistence/` only, so the ban applies to
// every file under this package the moment it exists. That is the "the fakes need no SwiftData
// import" done-when, held by a rule rather than by review.
//
// Not added to the Linux job. It would build there — that is the point of the edge above — but the
// job's steps are the two packages whose *requirements* name Linux, and a third step would imply
// this package carries NFR-0.2 too. The lint rule already covers what matters.
//
// `platforms:` is required, for the reason RepositoryInterface's manifest gives: the protocols'
// `async` requirements need iOS 13, and Xcode builds a clause-less package target against the SDK's
// own floor.
let package = Package(
    name: "RepositoryFakes",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RepositoryFakes", targets: ["RepositoryFakes"])
    ],
    dependencies: [
        .package(path: "../PowerliftingCore"),
        .package(path: "../RepositoryInterface"),
        .package(path: "../Persistence"),
    ],
    targets: [
        .target(
            name: "RepositoryFakes",
            dependencies: ["PowerliftingCore", "RepositoryInterface"],
            swiftSettings: strictSettings
        ),
        // G-6.3. The shared conformance suite: every test runs twice, once per subject. The
        // dependency on `Persistence` lives here and only here.
        .testTarget(
            name: "RepositoryFakesTests",
            dependencies: ["RepositoryFakes", "Persistence"],
            swiftSettings: strictSettings
        ),
    ]
)
