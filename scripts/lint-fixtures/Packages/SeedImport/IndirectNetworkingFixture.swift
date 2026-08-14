// Fixture: must trigger `no_networking_in_seed_import` (NFR-1.7, G-2.1).
//
// Deliberately not compiled — it lives outside every package's Sources/ and Tests/.
//
// The sibling fixture covers the shapes that name a networking type. These four do not name one:
// `Data(contentsOf:)` and `String(contentsOf:)` take a URL of any scheme and block on the network
// for an http(s) one, and `resourceBytes`/`lines` do the same asynchronously. A rule matching only
// `URLSession` and its siblings lets every one of them through, which is what it did until
// 2026-08-13.

import Foundation

struct IndirectNetworkingFixture {
    let url = URL(string: "https://cdn.example.com/exercises.json")!

    func viaData() throws -> Data { try Data(contentsOf: url) }
    func viaString() throws -> String { try String(contentsOf: url, encoding: .utf8) }
    func viaBytes() -> URL.AsyncBytes { url.resourceBytes }
    func viaLines() -> AsyncLineSequence<URL.AsyncBytes> { url.lines }
}
