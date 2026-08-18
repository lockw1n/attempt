// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings, for the same reasons, as the other feature packages — see the
// commented block in Packages/Features/ExerciseLibrary/Package.swift.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
]

// TR-1.3: the dashboard (FR-1.9).
//
// Same shape as every feature package: four dependencies, no `Persistence`, one level deeper than
// the rest of Packages/. All of that is argued once, in
// Packages/Features/ExerciseLibrary/Package.swift.
let package = Package(
    name: "Dashboard",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Dashboard", targets: ["Dashboard"])
    ],
    dependencies: [
        .package(path: "../../PowerliftingCore"),
        .package(path: "../../RepositoryInterface"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../AppNavigation"),
    ],
    targets: [
        .target(
            name: "Dashboard",
            dependencies: [
                "PowerliftingCore",
                "RepositoryInterface",
                "DesignSystem",
                "AppNavigation",
            ],
            swiftSettings: settings
        )
    ]
)
