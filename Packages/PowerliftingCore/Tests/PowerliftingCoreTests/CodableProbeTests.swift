import Testing

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
}
