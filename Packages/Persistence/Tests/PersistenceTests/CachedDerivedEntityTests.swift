import Foundation
import SwiftData
import Testing

@testable import Persistence

@Suite("Cached derived values")
struct CachedDerivedEntityTests {
    @Test("A row reports the rules version that produced it")
    func versionIsReported() {
        let cache = FixtureCacheEntity(computationVersion: 3)

        #expect(cache.wasComputed(byRulesVersion: 3))
        #expect(cache.wasComputed(byRulesVersion: 4) == false)
        #expect(cache.computationVersion == 3)
    }

    // A row whose version column was defaulted rather than written — what G-2.5 produces — must
    // match no real version, or a value nothing computed reads as current.
    @Test("A defaulted version matches no real rules version")
    func defaultedVersionMatchesNothing() {
        let defaulted = FixtureCacheEntity(computationVersion: 0)

        for version in 1...5 {
            #expect(defaulted.wasComputed(byRulesVersion: version) == false)
        }
        #expect(defaulted.computationVersion == 0)
    }
}
