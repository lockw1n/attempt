import Foundation
import Testing

@testable import Routines

@Suite("Routines copy")
struct RoutinesStringsTests {
    // G-3.4. A key with no entry in the catalogue renders its own identifier, which is what a
    // missing key looks like on screen — and nothing else in the chain catches one.
    @Test("Every string this module can draw resolves to something other than its key")
    func everyResourceResolves() {
        for resource in RoutinesStrings.allResources {
            let resolved = String(localized: resource)
            #expect(!resolved.isEmpty)
            #expect(
                resolved != resource.key,
                "unresolved key: \(resource.key)")
        }
    }
}
