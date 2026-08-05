import Testing

@testable import PowerliftingCore

// Tests for the test infrastructure. `CodableProbe` is the only thing standing between this
// module's wire formats and `JSONEncoder` (`NFR-0.2`, and CI cannot referee it — see the file
// header), and T-0.12 and T-0.20 are both expected to extend it. A probe that quietly gets an
// answer wrong is worse than no probe, because every assertion written against it inherits the
// mistake. These pin the two behaviours that are not obvious from reading it.

/// Encodes through two separately-requested keyed containers, which is legal `Codable`.
private struct TwoContainerValue: Encodable {
    enum CodingKeys: String, CodingKey {
        case first
        case second
    }

    func encode(to encoder: any Encoder) throws {
        var one = encoder.container(keyedBy: CodingKeys.self)
        try one.encode(1, forKey: .first)
        var two = encoder.container(keyedBy: CodingKeys.self)
        try two.encode(2, forKey: .second)
    }
}

/// The unkeyed twin of `TwoContainerValue`, and legal for the same reason.
private struct TwoUnkeyedContainerValue: Encodable {
    func encode(to encoder: any Encoder) throws {
        var one = encoder.unkeyedContainer()
        try one.encode(1)
        var two = encoder.unkeyedContainer()
        try two.encode(2)
    }
}

/// An array holding values of mixed shape, to prove elements are encoded by re-entering the
/// encoder rather than by this container deciding what they look like.
private struct MixedArrayValue: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode("belt")
        try container.encode(Weight(grams: 2_500))
        try container.encodeNil()
        try container.encode(true)
    }
}

@Suite("CodableProbe")
struct CodableProbeTests {
    @Test("Requesting the keyed container twice keeps the fields from both")
    func repeatedContainerRequestsAccumulate() throws {
        // Regression, found in review of T-0.13 and measured before the fix: a fresh accumulator
        // per `container(keyedBy:)` call reset the slot, so this encoded as `object(second: 2)`
        // and the first field vanished with no error. An encoder that silently truncates makes
        // every assertion written against it worthless.
        #expect(
            try probeEncode(TwoContainerValue())
                == .object([
                    ProbeField(key: "first", value: .int(1)),
                    ProbeField(key: "second", value: .int(2)),
                ]))
    }

    @Test("Requesting the unkeyed container twice keeps the elements from both")
    func repeatedUnkeyedContainerRequestsAccumulate() throws {
        // The unkeyed half of the same regression, built in from the start in T-0.12 because the
        // keyed path had already paid for the lesson. A fresh accumulator per `unkeyedContainer()`
        // call would encode this as `array(int(2))`, losing the first element with no error.
        #expect(try probeEncode(TwoUnkeyedContainerValue()) == .array([.int(1), .int(2)]))
    }

    @Test("Object equality is sensitive to key order")
    func objectEqualityIsOrdered() {
        // The mechanism behind pinning a wire format's key order, which is half of what byte
        // stability means. T-0.20 asserts per-case byte stability on top of this; if `.object`
        // ever compared as a dictionary, those assertions would pass on a reordered encoder.
        let increment = ProbeField(key: "increment", value: .int(2_500))
        let strategy = ProbeField(key: "strategy", value: .string("nearest"))
        #expect(ProbeValue.object([increment, strategy]) != .object([strategy, increment]))
        #expect(ProbeValue.object([increment, strategy]) == .object([increment, strategy]))
    }

    @Test("Array equality is sensitive to element order")
    func arrayEqualityIsOrdered() {
        #expect(ProbeValue.array([.int(1), .int(2)]) != .array([.int(2), .int(1)]))
        #expect(ProbeValue.array([.int(1), .int(2)]) == .array([.int(1), .int(2)]))
    }

    @Test("Array elements keep their own shapes")
    func arrayElementsKeepTheirOwnShapes() throws {
        // Each element re-enters the encoder, so a nested `Weight` stays a bare integer inside an
        // array exactly as it does inside an object.
        #expect(
            try probeEncode(MixedArrayValue())
                == .array([.string("belt"), .int(2_500), .null, .bool(true)]))
    }

    @Test("An array round-trips through both directions")
    func arraysRoundTrip() throws {
        let original = ["belt", "sleeves", "chains"]
        #expect(try probeEncode(original) == .array(original.map(ProbeValue.string)))
        #expect(try probeDecode([String].self, from: try probeEncode(original)) == original)
        #expect(try probeDecode([Int].self, from: .array([])) == [])
    }

    @Test("An empty array is distinct from a missing value")
    func emptyArrayEncodes() throws {
        #expect(try probeEncode([String]()) == .array([]))
    }

    @Test("Decoding an array from a non-array throws")
    func nonArrayThrowsOnUnkeyedDecoding() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode([String].self, from: .string("belt"))
        }
    }

    @Test("Decoding past the end of an array throws rather than trapping")
    func runningOffTheEndThrows() {
        // A fixed-size shape reading more elements than the payload holds is corrupt input, which
        // a decoder reports. Trapping here would take down the whole test run instead of one test.
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(ThreeElementValue.self, from: .array([.int(1), .int(2)]))
        }
    }

    @Test("An array element of the wrong type throws")
    func wrongElementTypeThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode([String].self, from: .array([.string("belt"), .int(1)]))
        }
    }
}

/// Reads a fixed three elements from an unkeyed container, so a short payload is an error rather
/// than a shorter result.
private struct ThreeElementValue: Decodable {
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        #expect(container.count == 2)
        #expect(!container.isAtEnd)
        for _ in 0..<3 {
            _ = try container.decode(Int.self)
        }
    }
}
