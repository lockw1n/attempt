// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same three settings as PowerliftingCore — see the commented block in
// Packages/PowerliftingCore/Package.swift for what each one buys.
//
// `.defaultIsolation(nil)` stays for the token layer, and that is now a decision rather than a
// placeholder: tokens are pure values with no view code in them, and MainActor-isolating them would
// force every test that reads a palette entry into an actor hop for nothing. The components target
// (TR-1.4, T-1.03) is where flipping to `.defaultIsolation(MainActor.self)` becomes the right call —
// default isolation is a per-target setting for exactly this reason.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// TR-1.4: design tokens, components and theme.
//
// TWO TARGETS ON PURPOSE. `DesignTokens` holds the spacing, type and colour scales and no views;
// `DesignSystem` holds the components built from them (T-1.03) and re-exports the tokens, so a
// feature that only needs a palette entry — a store, a formatter, a preview fixture — can import
// the scales without the component surface coming with them.
let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DesignTokens", targets: ["DesignTokens"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DesignTokens",
            swiftSettings: strictSettings
        ),
        .target(
            name: "DesignSystem",
            dependencies: ["DesignTokens"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "DesignTokensTests",
            dependencies: ["DesignTokens"],
            swiftSettings: strictSettings
        ),
    ]
)
