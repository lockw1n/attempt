// Fixture: must trigger `no_networking_in_seed_import` (NFR-1.7, G-2.1).
//
// Deliberately not compiled — it lives outside every package's Sources/ and Tests/. Two shapes,
// because there are two ways the importer could acquire a network: reaching for URLSession inside
// the module, and importing a networking framework so that it can.

import Foundation
import Network

struct NetworkingFixture {
    func fetchCatalogue(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: URLRequest(url: url))
        return data
    }
}
