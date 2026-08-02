// swift-tools-version: 6.2

import PackageDescription

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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // G-6.3. No coverage threshold applies here — G-6.1 names PowerliftingCore only.
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
