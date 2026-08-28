import Foundation
import PowerliftingCore
import Testing

@testable import Settings

/// The unit crossing every outside bodyweight reading makes (`G-1.1`, `FR-1.8.2`).
///
/// A suite of its own because this is the whole of what ``HealthBodyweightSource`` does that can be
/// wrong: the query around it needs a real health store and no test can reach it, so the
/// arithmetic is kept out here where one can.
@Suite("Bodyweight sample")
struct BodyweightSampleTests {
    /// Arbitrary, and only ever compared with itself: what these tests pin is the crossing, not
    /// the identity, which this type carries through untouched.
    private static let id = UUID()
    private static let date = Date(timeIntervalSince1970: 1_707_030_000)

    @Test("Kilograms cross into whole grams and keep the source's identity and instant")
    func kilogramsBecomeGrams() throws {
        let sample = try #require(
            BodyweightSample.fromKilograms(82.4, id: Self.id, date: Self.date))

        #expect(sample.weight == Weight(grams: 82_400))
        #expect(sample.id == Self.id)
        #expect(sample.date == Self.date)
    }

    @Test("A reading finer than a gram rounds to the nearest one, up and down")
    func subGramReadingsRoundToNearest() throws {
        // A scale reporting more precision than grams is the ordinary case, not an edge one.
        #expect(
            try #require(BodyweightSample.fromKilograms(82.400_4, id: Self.id, date: Self.date))
                .weight == Weight(grams: 82_400))
        #expect(
            try #require(BodyweightSample.fromKilograms(82.400_6, id: Self.id, date: Self.date))
                .weight == Weight(grams: 82_401))
    }

    @Test("A value that is not a mass is refused rather than stored as something else")
    func unusableReadingsAreRefused() {
        #expect(BodyweightSample.fromKilograms(.nan, id: Self.id, date: Self.date) == nil)
        #expect(BodyweightSample.fromKilograms(.infinity, id: Self.id, date: Self.date) == nil)
        #expect(
            BodyweightSample.fromKilograms(.greatestFiniteMagnitude, id: Self.id, date: Self.date)
                == nil)
    }

    @Test("Zero is a storable reading — refusing a mass is not this type's job")
    func zeroIsStorable() throws {
        // The planner decides what is usable; this crossing only decides what is representable.
        #expect(
            try #require(BodyweightSample.fromKilograms(0, id: Self.id, date: Self.date))
                .weight == .zero)
    }
}
