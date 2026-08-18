// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same three settings as the other packages — see the commented block in
// Packages/PowerliftingCore/Package.swift for what each one buys.
//
// `.defaultIsolation(nil)`, as in DesignTokens: nothing here is a `View`. The one type that has to
// be on the main actor — `NavigationState`, which a SwiftUI view binds to — says so at its own
// declaration, and everything else (the routes, the tabs, the snapshot) is a value a test should be
// able to read without an actor hop.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
]

// TR-1.1: the typed navigation model — four tabs, one namespaced `Route` enum, and a serializable
// snapshot of where the user is.
//
// IT HOLDS NO VIEWS AND NO USER-VISIBLE STRINGS, both on purpose. The root `TabView` lives in the
// app target because that is where tab titles can be localized against the main bundle (G-3.4, the
// same rule DesignSystem states for its components), and because this package exists to be tested:
// the Xcode project has one target and no test target (Q-1.3), so anything that needs a unit test
// has to live under Packages/.
//
// The `platforms:` clause is required, not decorative: `NavigationState` is `@Observable` and hands
// out a SwiftUI `Binding`, and a clause-less package target is compiled against the SDK's own floor
// by Xcode even though `swift build` on macOS passes.
let package = Package(
    name: "AppNavigation",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AppNavigation", targets: ["AppNavigation"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppNavigation",
            swiftSettings: settings
        ),
        .testTarget(
            name: "AppNavigationTests",
            dependencies: ["AppNavigation"],
            swiftSettings: settings
        ),
    ]
)
