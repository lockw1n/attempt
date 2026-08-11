import Foundation
import PowerliftingCore
import Testing

@testable import Persistence

// Every default is pinned to a literal rather than to the expression that produces it, for the
// reason T-0.11's raw-value tests give: comparing `SchemaDefaults.movement` with
// `Movement.other.rawValue` only proves the constant agrees with itself.
//
// What these cannot check is that SwiftData records these values as the store's *column* defaults.
// Observing that needs a two-version store, which is T-0.34's apparatus and where the probe belongs.
@Suite("Schema defaults")
struct SchemaDefaultsTests {
    // G-2.5 forces a default onto every non-optional join key. A stable sentinel is what lets one
    // predicate find every unwritten reference; UUID() would mint a distinct dangling one per row.
    @Test("An unwritten join key is the all-zero UUID")
    func unlinkedIDIsTheZeroUUID() {
        #expect(SchemaDefaults.unlinkedID.uuidString == "00000000-0000-0000-0000-000000000000")
    }

    @Test("The vocabulary defaults are the deliberate cases, by spelling")
    func vocabularyDefaults() {
        #expect(SchemaDefaults.movement == "other")
        #expect(SchemaDefaults.equipment == "other")
        #expect(SchemaDefaults.laterality == "bilateral")
        #expect(SchemaDefaults.barType == "other")
    }

    // A spelling that no case answers to would leave the repository's mapping with nothing to fall
    // back to, which is the whole point of choosing these four.
    @Test("Each vocabulary default names a real case")
    func vocabularyDefaultsResolve() {
        #expect(Movement(rawValue: SchemaDefaults.movement) == .other)
        #expect(Equipment(rawValue: SchemaDefaults.equipment) == .other)
        #expect(Laterality(rawValue: SchemaDefaults.laterality) == .bilateral)
        #expect(BarType(rawValue: SchemaDefaults.barType) == .other)
    }

    // Zero here would silently flatten every tonnage figure to nothing.
    @Test("An exercise loads one implement unless it says otherwise")
    func implementCountDefault() {
        #expect(SchemaDefaults.implementCount == 1)
    }

    // TR-0.2.8's tie-break resolves to the earlier set, so a distant-past sentinel here would win
    // every tie a session with no written date took part in. Minted per read, like `id` and unlike
    // `unlinkedID` — a session that arrives without a date is not the same session as any other.
    @Test("An unwritten session date is the present, not a sentinel")
    func sessionDateIsNotASentinel() {
        #expect(SchemaDefaults.sessionDate.timeIntervalSinceNow > -1)
        #expect(SchemaDefaults.sessionDate > Date(timeIntervalSince1970: 1_700_000_000))
    }

    // G-1.8: a set nobody classified must not read as a completed working set, because that is the
    // one combination analytics counts — and a personal record, once badged, outlives its row.
    @Test("An unclassified set is neither a warmup nor completed")
    func setFlagDefaults() {
        #expect(SchemaDefaults.isWarmup == false)
        #expect(SchemaDefaults.isCompleted == false)
    }
}
