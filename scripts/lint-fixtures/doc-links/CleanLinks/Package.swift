// swift-tools-version: 6.2
//
// Fixture for scripts/check-doc-links.sh --self-test. Not a real package: nothing depends on it,
// nothing builds it but the self-test, and it lives outside Packages/ so the gate's own globs —
// and swiftlint's `included:` — do not reach it.
import PackageDescription

let package = Package(
    name: "CleanLinks",
    products: [.library(name: "CleanLinks", targets: ["CleanLinks"])],
    targets: [
        .target(name: "CleanLinks"),
        .testTarget(name: "CleanLinksTests", dependencies: ["CleanLinks"]),
    ]
)
