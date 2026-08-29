// swift-tools-version: 6.2
//
// Fixture for scripts/check-doc-links.sh --self-test. See CleanLinks/Package.swift.
import PackageDescription

let package = Package(
    name: "CrossBase",
    products: [.library(name: "CrossBase", targets: ["CrossBase"])],
    targets: [.target(name: "CrossBase")]
)
