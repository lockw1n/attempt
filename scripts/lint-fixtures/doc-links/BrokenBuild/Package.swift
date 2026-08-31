// swift-tools-version: 6.2
//
// Fixture for scripts/check-doc-links.sh --self-test. See CleanLinks/Package.swift. This one does
// not compile, on purpose: the gate tolerates a failed extraction, so something has to prove that
// a module which produced no graph is still a loud failure rather than nothing to report.
import PackageDescription

let package = Package(
    name: "BrokenBuild",
    products: [.library(name: "BrokenBuild", targets: ["BrokenBuild"])],
    targets: [.target(name: "BrokenBuild")]
)
