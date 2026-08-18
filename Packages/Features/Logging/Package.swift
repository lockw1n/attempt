// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings, for the same reasons, as the other feature packages — see the
// commented block in Packages/Features/ExerciseLibrary/Package.swift.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
]

// TR-1.3: workout logging (FR-1.2).
//
// Same shape as every feature package: four dependencies, no `Persistence`, one level deeper than
// the rest of Packages/. All of that is argued once, in
// Packages/Features/ExerciseLibrary/Package.swift.
// THE FIFTH DEPENDENCY IS TEST-ONLY — `RepositoryFakes`, on the test target alone. Why that keeps
// TR-0.1.2 intact is argued once, in Packages/Features/Settings/Package.swift.
let package = Package(
    name: "Logging",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Logging", targets: ["Logging"])
    ],
    dependencies: [
        .package(path: "../../PowerliftingCore"),
        .package(path: "../../RepositoryInterface"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../AppNavigation"),
        .package(path: "../../RepositoryFakes"),
    ],
    targets: [
        .target(
            name: "Logging",
            dependencies: [
                "PowerliftingCore",
                "RepositoryInterface",
                "DesignSystem",
                "AppNavigation",
            ],
            swiftSettings: settings
        ),
        .testTarget(
            name: "LoggingTests",
            dependencies: ["Logging", "RepositoryFakes"],
            swiftSettings: settings
        ),
    ]
)
