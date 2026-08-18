// swift-tools-version: 6.2

import PackageDescription

// G-6.4 (T-0.06). Same two settings as every other package here — see the commented block in
// Packages/PowerliftingCore/Package.swift for what each one buys.
//
// `.defaultIsolation(MainActor.self)`, as in the DesignSystem component layer and unlike everything
// under it: a feature module holds `View`s and the `@Observable` stores they bind to (TR-1.2), both
// of which SwiftUI already requires on the main actor. `nil` here would mean writing `@MainActor`
// on each one and taking a diagnostic on whichever was forgotten.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
]

// TR-1.3: the exercise library (FR-1.1). THIS MANIFEST IS THE EXEMPLAR the other four feature
// packages point at — read it before changing any of them.
//
// THE FEATURE PACKAGES SIT ONE LEVEL DEEPER THAN EVERY OTHER PACKAGE, under Packages/Features/,
// and that is load-bearing rather than tidy: `.swiftlint.yml` scopes all six G-7.7 no-raw-values
// rules to `Packages/Features/.*`, written before any feature existed. A feature module anywhere
// else is outside those rules the day their matching is tightened. The cost of the extra level is
// that a gate walking `Packages/*` does not see one: `scripts/build-packages.sh` (the warnings
// gate) and `scripts/check-doc-ratio.sh` each needed a second glob, and anything added later that
// walks the tree needs the same.
//
// THE FOUR DEPENDENCIES ARE THE POINT OF THIS PACKAGE EXISTING BEFORE ANY SCREEN DOES, and the
// absence of a fifth is half of TR-0.1.2:
//
//   RepositoryInterface   the only way storage is reached. `Persistence` is NOT a dependency, so
//                         `import Persistence` from a feature does not resolve. That is one
//                         direction only, and the other is NOT enforced: adding
//                         `.package(path: "../../Persistence")` below makes the import resolve and
//                         no gate objects, so the absence of that line stays a rule to remember.
//                         `no_swiftdata_outside_persistence` does not cover it either — it is
//                         path-scoped and so reached these five the moment they existed, but it
//                         catches `import SwiftData` (which resolves against the SDK from any
//                         target on Darwin) and a feature reaching storage through `Persistence`'s
//                         own API imports `Persistence`, not `SwiftData`.
//   PowerliftingCore      every record type in the repository signatures above is written in the
//                         domain's own types (`Weight`, `RoundingRule`), so a feature that touches
//                         a record needs this edge to name what it got back.
//   DesignSystem          the component layer, which re-exports the token scales — G-7.7 forbids a
//                         feature declaring a raw value of its own.
//   AppNavigation         the typed Route. A screen pushes `NavigationLink(value:)` and owns a
//                         sub-enum of destinations; neither is reachable without importing it.
//
// `platforms:` is required, not decorative — the repository protocols are `async` and the views
// will be SwiftUI. A clause-less package target is compiled by Xcode against the SDK's own floor
// while `swift build` on macOS passes; see the trap in PowerliftingCore's manifest.
let package = Package(
    name: "ExerciseLibrary",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ExerciseLibrary", targets: ["ExerciseLibrary"])
    ],
    dependencies: [
        .package(path: "../../PowerliftingCore"),
        .package(path: "../../RepositoryInterface"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../AppNavigation"),
    ],
    targets: [
        .target(
            name: "ExerciseLibrary",
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
