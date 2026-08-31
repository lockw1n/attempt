// swift-tools-version: 6.2
//
// Fixture for scripts/check-doc-links.sh --self-test. Depends on CrossBase, which is the whole
// point: this pair proves what no single-module fixture can — that a link into a sibling module
// resolves only when the module is named in the path, and only when both graphs are in the one
// `docc convert` run. Sixty of this repo's doc comments rest on both halves.
import PackageDescription

let package = Package(
    name: "CrossUser",
    products: [.library(name: "CrossUser", targets: ["CrossUser"])],
    dependencies: [.package(path: "../CrossBase")],
    targets: [
        .target(
            name: "CrossUser",
            dependencies: [.product(name: "CrossBase", package: "CrossBase")]
        )
    ]
)
