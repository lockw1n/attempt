// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same three settings as PowerliftingCore, and for the same reasons — see the
// commented block in Packages/PowerliftingCore/Package.swift.
//
// `.defaultIsolation(nil)` is the deliberate choice here too, not an oversight: repositories are
// called from whatever context owns them (TR-0.4.1), so isolation belongs on the individual
// @ModelActor or actor that needs it, not on the whole module.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
    .treatAllWarnings(as: .error)
]

// TR-0.1: SwiftData models and repository implementations.
// TR-0.1.2: this is the ONLY target permitted to import SwiftData. Everything else reaches
// storage through the repository protocols, which expose domain value types and DTOs only
// (TR-0.4.3).
let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../PowerliftingCore")
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: ["PowerliftingCore"],
            swiftSettings: strictSettings
        ),
        // G-6.3. No coverage threshold applies here — G-6.1 names PowerliftingCore only.
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
            swiftSettings: strictSettings
        )
    ]
)
