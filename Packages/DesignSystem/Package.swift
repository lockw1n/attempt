// swift-tools-version: 6.2

import PackageDescription

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
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
