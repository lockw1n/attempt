// swift-tools-version: 6.2
// (6.2 is the minimum that knows about `.v26`; see the iOS 26 decision in
//  docs/phase-0/open-questions.md → Q-0.1. CI images must be Swift 6.2+.)

import PackageDescription

// TR-0.1: pure Swift domain layer.
// TR-0.1.1 / NFR-0.2: this package must compile on Linux, which is the mechanical proof that
// no Apple framework has leaked in. The `dependencies` array below is empty and must stay that
// way — see docs/phase-0/tasks/T-0.02-restructure-into-packages.md.
// No `platforms:` clause on purpose. This package touches no Apple API, so it has nothing to
// gate on a platform version — and declaring a minimum would be worse than redundant: it would
// require that SDK to be present just to build, breaking the Linux job (TR-0.1.1) and pinning
// every CI runner to a specific Xcode. Consumers declare their own minimums.
let package = Package(
    name: "PowerliftingCore",
    products: [
        .library(name: "PowerliftingCore", targets: ["PowerliftingCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PowerliftingCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
