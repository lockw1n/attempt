// swift-tools-version: 6.2
//
// FIXTURE — not part of the app. Deliberately contains code that emits a compiler warning, so
// scripts/verify-warnings-gate.sh can prove that `-warnings-as-errors` still turns that warning
// into a build failure.
//
// It lives under scripts/ rather than Packages/ on purpose: `build-packages.sh` globs
// `Packages/*/Package.swift`, and a package that always fails to build would break every run.
//
// Note this manifest does NOT set `.treatAllWarnings(as: .error)`. That is the whole point — the
// gate now comes from the command-line flags in swift-strict-flags.sh, and this fixture proves
// the flags are what does the work, by building clean without them and failing with them.

import PackageDescription

let package = Package(
    name: "WarningGateFixture",
    products: [
        .library(name: "WarningGateFixture", targets: ["WarningGateFixture"])
    ],
    targets: [
        .target(name: "WarningGateFixture")
    ]
)
