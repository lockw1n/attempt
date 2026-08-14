import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).

/// Builds a table, failing the test rather than force unwrapping.
private func rpeTable(
    _ entries: [RPETable.Entry], repRange: ClosedRange<Int> = 1...10
) throws -> RPETable {
    try #require(RPETable(entries: entries, repRange: repRange))
}

@Suite("RPETable — wire format")
struct RPETableCodableTests {
    // `TR-0.5.2` publishes this shape at `/content/v1/formulas.json`. As with
    // `RoundingRuleCodableTests`, this suite pins key spelling and key order, not just a round
    // trip — `ProbeValue.object` compares fields in the position they were written.

    private let twoRowShape = ProbeValue.object([
        ProbeField(
            key: "entries",
            value: .array([
                .object([
                    ProbeField(key: "repsToFailure", value: .double(1)),
                    ProbeField(key: "fractionOfMax", value: .double(1.0)),
                ]),
                .object([
                    ProbeField(key: "repsToFailure", value: .double(6)),
                    ProbeField(key: "fractionOfMax", value: .double(0.837)),
                ]),
            ])
        ),
        ProbeField(key: "repRangeLowerBound", value: .int(1)),
        ProbeField(key: "repRangeUpperBound", value: .int(10)),
    ])

    private func twoRowTable() throws -> RPETable {
        try rpeTable([
            RPETable.Entry(repsToFailure: 1, fractionOfMax: 1.0),
            RPETable.Entry(repsToFailure: 6, fractionOfMax: 0.837),
        ])
    }

    @Test("Encodes entries then the rep-range bounds, in that order")
    func encodesAsPinnedObject() throws {
        #expect(try probeEncode(twoRowTable()) == twoRowShape)
    }

    @Test("Round-trips through Codable, including the shipped chart")
    func roundTripsThroughCodable() throws {
        for table in try [twoRowTable(), RPETable.standard] {
            #expect(try probeDecode(RPETable.self, from: try probeEncode(table)) == table)
        }
    }

    @Test("Encode → decode → encode is byte-stable")
    func encodingIsStableAcrossARoundTrip() throws {
        let first = try probeEncode(twoRowTable())
        let second = try probeEncode(try probeDecode(RPETable.self, from: first))
        #expect(first == second)
    }

    @Test("Decoding accepts the keys in any order")
    func decodingIsOrderInsensitive() throws {
        let reordered = ProbeValue.object([
            ProbeField(key: "repRangeUpperBound", value: .int(10)),
            ProbeField(key: "repRangeLowerBound", value: .int(1)),
            ProbeField(
                key: "entries",
                value: .array([
                    .object([
                        ProbeField(key: "repsToFailure", value: .double(1)),
                        ProbeField(key: "fractionOfMax", value: .double(1.0)),
                    ]),
                    .object([
                        ProbeField(key: "repsToFailure", value: .double(6)),
                        ProbeField(key: "fractionOfMax", value: .double(0.837)),
                    ]),
                ])
            ),
        ])
        let expected = try twoRowTable()
        #expect(try probeDecode(RPETable.self, from: reordered) == expected)
        // …and re-encoding puts them back in the pinned order.
        #expect(try probeEncode(try probeDecode(RPETable.self, from: reordered)) == twoRowShape)
    }

    @Test("A rep-range upper bound below the lower bound throws rather than trapping")
    func invertedRepRangeThrowsRatherThanTrapping() {
        // `lower...upper` is a precondition failure when `lower > upper` — the guard this test
        // exists for is the one thing `RPETable.init(entries:repRange:)` alone cannot check,
        // because by the time that initialiser runs, `ClosedRange` construction has already either
        // succeeded or crashed the process. A remote payload is exactly the input that can send 10
        // and 1 in that order.
        let corrupt = ProbeValue.object([
            ProbeField(
                key: "entries",
                value: .array([
                    .object([
                        ProbeField(key: "repsToFailure", value: .double(1)),
                        ProbeField(key: "fractionOfMax", value: .double(1.0)),
                    ])
                ])
            ),
            ProbeField(key: "repRangeLowerBound", value: .int(10)),
            ProbeField(key: "repRangeUpperBound", value: .int(1)),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RPETable.self, from: corrupt)
        }
    }

    @Test(
        "Decoding enforces the same entry invariants as the initialiser",
        arguments: [
            // Empty entries.
            ProbeValue.array([]),
            // A fraction authored as a published percentage rather than a ratio.
            ProbeValue.array([
                .object([
                    ProbeField(key: "repsToFailure", value: .double(1)),
                    ProbeField(key: "fractionOfMax", value: .double(83.7)),
                ])
            ]),
            // Non-ascending keys.
            ProbeValue.array([
                .object([
                    ProbeField(key: "repsToFailure", value: .double(2)),
                    ProbeField(key: "fractionOfMax", value: .double(0.9)),
                ]),
                .object([
                    ProbeField(key: "repsToFailure", value: .double(1)),
                    ProbeField(key: "fractionOfMax", value: .double(0.95)),
                ]),
            ]),
        ]
    )
    func decodingEnforcesEntryInvariants(entries: ProbeValue) {
        let corrupt = ProbeValue.object([
            ProbeField(key: "entries", value: entries),
            ProbeField(key: "repRangeLowerBound", value: .int(1)),
            ProbeField(key: "repRangeUpperBound", value: .int(10)),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RPETable.self, from: corrupt)
        }
    }

    @Test("A rep-range floor below 1 throws")
    func decodingEnforcesRepRangeFloor() {
        let corrupt = ProbeValue.object([
            ProbeField(
                key: "entries",
                value: .array([
                    .object([
                        ProbeField(key: "repsToFailure", value: .double(1)),
                        ProbeField(key: "fractionOfMax", value: .double(1.0)),
                    ])
                ])
            ),
            ProbeField(key: "repRangeLowerBound", value: .int(0)),
            ProbeField(key: "repRangeUpperBound", value: .int(10)),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RPETable.self, from: corrupt)
        }
    }

    @Test("A missing key throws")
    func missingKeyThrows() {
        let truncated = ProbeValue.object([
            ProbeField(key: "repRangeLowerBound", value: .int(1)),
            ProbeField(key: "repRangeUpperBound", value: .int(10)),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RPETable.self, from: truncated)
        }
    }

    @Test("A non-object throws")
    func nonObjectThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RPETable.self, from: .int(1))
        }
    }
}
