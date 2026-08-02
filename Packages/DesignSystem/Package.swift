// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same three settings as PowerliftingCore — see the commented block in
// Packages/PowerliftingCore/Package.swift for what each one buys.
//
// `.defaultIsolation(nil)` here is the conservative choice for an empty package, not a considered
// verdict on a UI module: it matches SwiftPM's own default and the other two packages, so nothing
// is silently decided before there is code. When the tokens and components land in Phase 1
// (TR-1.4), flipping this package — and only this package — to
// `.defaultIsolation(MainActor.self)` is a legitimate call; SwiftUI views are MainActor-isolated
// anyway, and default isolation is a per-target setting for exactly this reason.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
    .treatAllWarnings(as: .error)
]

// TR-0.1: design tokens, components and theme.
// Deliberately empty in Phase 0 — G-7 is a constraint on this package, not a Phase 0 deliverable.
// The tokens arrive in Phase 1 (TR-1.4). See docs/phase-0/coverage.md → "Known gaps" §1.
let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DesignSystem",
            swiftSettings: strictSettings
        )
    ]
)
