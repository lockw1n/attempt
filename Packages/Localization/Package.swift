// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings as DesignTokens, for the same reason: everything here is a
// value type with no view code in it, so MainActor isolation would buy an actor hop per format
// call and nothing else.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// G-3.4: the localisation layer — the key convention every module's catalogue follows, and the
// locale-explicit format styles that keep a rendered number out of string interpolation.
//
// A PACKAGE RATHER THAN A DESIGNSYSTEM TARGET, because formatting a weight means naming
// `PowerliftingCore.Weight`, and DesignSystem depends on nothing on purpose (TR-1.4) — a design
// system that knows the domain is no longer a design system. It carries no copy of its own: unit
// symbols and separators come from ICU, and the modules own their own strings.
let package = Package(
    name: "Localization",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Localization", targets: ["Localization"])
    ],
    dependencies: [
        .package(path: "../PowerliftingCore")
    ],
    targets: [
        .target(
            name: "Localization",
            dependencies: ["PowerliftingCore"],
            swiftSettings: settings
        ),
        .testTarget(
            name: "LocalizationTests",
            dependencies: ["Localization"],
            swiftSettings: settings
        ),
    ]
)
