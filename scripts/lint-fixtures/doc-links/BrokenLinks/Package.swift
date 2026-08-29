// swift-tools-version: 6.2
//
// Fixture for scripts/check-doc-links.sh --self-test. See CleanLinks/Package.swift.
import PackageDescription

let package = Package(
    name: "BrokenLinks",
    products: [.library(name: "BrokenLinks", targets: ["BrokenLinks"])],
    targets: [.target(name: "BrokenLinks")]
)
