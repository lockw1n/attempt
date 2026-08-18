// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same three settings as PowerliftingCore — see the commented block in
// Packages/PowerliftingCore/Package.swift for what each one buys.
//
// `.defaultIsolation(nil)` stays for the token layer: tokens are pure values with no view code in
// them, and MainActor-isolating them would force every test that reads a palette entry into an actor
// hop for nothing.
let tokenSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// The component layer takes the opposite default, which is what default isolation being a per-target
// setting is for. Every type here is a `View` or a `ButtonStyle`, both of which SwiftUI already
// requires on the main actor, so `nil` would mean writing `@MainActor` on each one and getting a
// diagnostic on whichever one was forgotten.
//
// The exception is the data-shaped enums a component's token choices are exposed through —
// `CardElevation`, `DeltaDirection`, `PrimaryActionWidth`. Those are marked `nonisolated` at the
// declaration: a MainActor-isolated `static var allCases` cannot satisfy `CaseIterable`, whose
// requirement is not, and a test asserting on a colour mapping should not have to hop to the main
// actor to read one.
let componentSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
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
            swiftSettings: tokenSettings
        ),
        .target(
            name: "DesignSystem",
            dependencies: ["DesignTokens"],
            swiftSettings: componentSettings
        ),
        .testTarget(
            name: "DesignTokensTests",
            dependencies: ["DesignTokens"],
            swiftSettings: tokenSettings
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            swiftSettings: componentSettings
        ),
    ]
)
