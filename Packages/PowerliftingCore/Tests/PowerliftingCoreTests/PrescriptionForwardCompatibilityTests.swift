import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// NFR-2.3 is the requirement under test: a prescription written by a newer app version must degrade
// gracefully rather than corrupt the program. "Gracefully" is read here as *preserved whole* — the
// discriminator, the version and every payload key — because a program is the user's own data and
// nothing re-supplies it. That is the opposite of what `Movement` does with a value it does not
// recognise, and the rule producing both answers is in CLAUDE.md.

/// A prescription type no version of this app knows, with a payload covering every shape a value
/// can take: object, array, string, number of both kinds, bool and null.
///
/// Its payload keys are in sorted order, which is the order this module writes them back in — so
/// ``PrescriptionUnknownTypeTests/itReEncodesToWhatArrived()`` can assert byte identity rather than
/// the weaker stability claim. A scrambled version is used where the sorting itself is under test.
let futurePrescription = ProbeValue.object([
    ProbeField(key: "version", value: .int(2)),
    ProbeField(key: "type", value: .string("wavePercent")),
    ProbeField(key: "autoRegulate", value: .bool(true)),
    ProbeField(key: "base", value: .double(0.7)),
    ProbeField(key: "cap", value: .int(200_000)),
    ProbeField(key: "ceiling", value: .null),
    ProbeField(key: "label", value: .string("wave 3")),
    ProbeField(
        key: "rounding",
        value: .object([
            ProbeField(key: "increment", value: .int(2_500)),
            ProbeField(key: "strategy", value: .string("nearest")),
        ])),
    ProbeField(key: "steps", value: .array([.double(0.7), .double(0.8), .double(0.9)])),
])

@Suite("Prescription — an unknown type from a newer version")
struct PrescriptionUnknownTypeTests {
    @Test("It decodes rather than throwing")
    func anUnknownTypeDoesNotThrow() throws {
        let decoded = try probeDecode(Prescription.self, from: futurePrescription)
        guard case .unrecognised(let preserved) = decoded else {
            Issue.record("Expected a preserved prescription, got \(decoded)")
            return
        }
        #expect(preserved.kind == "wavePercent")
        #expect(decoded.isRecognised == false)
    }

    @Test("The version it arrived under is preserved, not replaced with the current one")
    func theArrivingVersionSurvives() throws {
        // Re-stamping it as version 1 would claim this app understood it. It did not.
        guard case .unrecognised(let preserved) = try probeDecode(Prescription.self, from: futurePrescription)
        else {
            Issue.record("Expected a preserved prescription")
            return
        }
        #expect(preserved.schemaVersion == 2)
        #expect(preserved.schemaVersion != Prescription.currentSchemaVersion)
    }

    @Test("Every payload value survives, whatever its shape")
    func thePayloadSurvivesWhole() throws {
        guard case .unrecognised(let preserved) = try probeDecode(Prescription.self, from: futurePrescription)
        else {
            Issue.record("Expected a preserved prescription")
            return
        }
        #expect(
            preserved.payload == [
                "base": .double(0.7),
                "cap": .int(200_000),
                "label": .string("wave 3"),
                "autoRegulate": .bool(true),
                "ceiling": .null,
                "steps": .array([.double(0.7), .double(0.8), .double(0.9)]),
                "rounding": .object(["increment": .int(2_500), "strategy": .string("nearest")]),
            ])
    }

    @Test("The envelope keys are not part of the payload")
    func theEnvelopeIsNotPayload() throws {
        guard case .unrecognised(let preserved) = try probeDecode(Prescription.self, from: futurePrescription)
        else {
            Issue.record("Expected a preserved prescription")
            return
        }
        #expect(preserved.payload["version"] == nil)
        #expect(preserved.payload["type"] == nil)
        #expect(preserved.payload.count == 7)
    }

    @Test("It re-encodes to the same bytes it arrived as")
    func itReEncodesToWhatArrived() throws {
        // Byte identity, not merely stability: the fixture's keys are already in the order this
        // module writes them, so nothing at all changes on the way through.
        let decoded = try probeDecode(Prescription.self, from: futurePrescription)
        #expect(try probeEncode(decoded) == futurePrescription)
    }

    @Test("Payload keys are written sorted, whatever order they arrived in")
    func payloadKeysAreCanonicalisedOnTheWayOut() throws {
        let scrambled = ProbeValue.object([
            ProbeField(key: "version", value: .int(2)),
            ProbeField(key: "type", value: .string("wavePercent")),
            ProbeField(key: "steps", value: .array([.int(1)])),
            ProbeField(key: "base", value: .double(0.7)),
            ProbeField(key: "cap", value: .int(200_000)),
        ])
        let expected = ProbeValue.object([
            ProbeField(key: "version", value: .int(2)),
            ProbeField(key: "type", value: .string("wavePercent")),
            ProbeField(key: "base", value: .double(0.7)),
            ProbeField(key: "cap", value: .int(200_000)),
            ProbeField(key: "steps", value: .array([.int(1)])),
        ])
        // Sorted rather than as-received because a decoder's key order is not recoverable — there
        // is no order to preserve, only one to choose. Choosing makes re-encoding stable.
        #expect(try probeEncode(try probeDecode(Prescription.self, from: scrambled)) == expected)
    }

    @Test("Encode → decode → encode is byte-stable")
    func preservationIsStableAcrossARoundTrip() throws {
        let first = try probeEncode(try probeDecode(Prescription.self, from: futurePrescription))
        let second = try probeEncode(try probeDecode(Prescription.self, from: first))
        #expect(first == second)
    }

    @Test("An unknown type with no payload at all is still preserved")
    func anEmptyPayloadIsPreserved() throws {
        let bare = encodedPrescription("wavePercent", version: 3)
        let decoded = try probeDecode(Prescription.self, from: bare)
        guard case .unrecognised(let preserved) = decoded else {
            Issue.record("Expected a preserved prescription, got \(decoded)")
            return
        }
        #expect(preserved.payload.isEmpty)
        #expect(try probeEncode(decoded) == bare)
    }
}

@Suite("Prescription — a known type from a newer version")
struct PrescriptionNewerVersionTests {
    // The deliberate half of the version policy. A recognised spelling is read whatever the version
    // says, because refusing to read a `.fixedWeight` on account of the number beside it would be
    // the corruption NFR-2.3 exists to prevent rather than protection from it. What makes that safe
    // is the rule on `PrescriptionKind`: a spelling's meaning never changes, so a later version can
    // only ever add to what is here.

    @Test("A known type under a newer version still decodes", arguments: [2, 7, Int.max])
    func aKnownTypeFromANewerVersionDecodes(version: Int) throws {
        let future = encodedPrescription("fixedWeight", [("weight", .int(102_500))], version: version)
        #expect(try probeDecode(Prescription.self, from: future) == .fixedWeight(Weight(grams: 102_500)))
    }

    @Test("…and re-encodes at the current version")
    func aKnownTypeIsRewrittenAtTheCurrentVersion() throws {
        // Deliberate, and the one place the round trip is not byte-identical: the value is now one
        // this app understands, so it writes what it understands.
        let future = encodedPrescription("fixedWeight", [("weight", .int(102_500))], version: 9)
        let expected = encodedPrescription("fixedWeight", [("weight", .int(102_500))], version: 1)
        #expect(try probeEncode(try probeDecode(Prescription.self, from: future)) == expected)
    }

    @Test("Keys a newer version added to a known type are dropped")
    func extraKeysOnAKnownTypeAreLost() throws {
        // The documented cost of the policy above, pinned so it is a decision rather than a
        // surprise: preservation covers an unknown *type*, not an unknown *field* of a known one.
        let future = ProbeValue.object([
            ProbeField(key: "version", value: .int(2)),
            ProbeField(key: "type", value: .string("fixedWeight")),
            ProbeField(key: "weight", value: .int(102_500)),
            ProbeField(key: "cap", value: .int(200_000)),
        ])
        let decoded = try probeDecode(Prescription.self, from: future)
        #expect(decoded == .fixedWeight(Weight(grams: 102_500)))
        #expect(
            try probeEncode(decoded) == encodedPrescription("fixedWeight", [("weight", .int(102_500))]))
    }
}

@Suite("PreservedValue — every shape round-trips")
struct PreservedValueTests {
    @Test(
        "Each case encodes to its own shape and decodes back",
        arguments: [
            (PreservedValue.null, ProbeValue.null),
            (.bool(true), .bool(true)),
            (.bool(false), .bool(false)),
            (.int(0), .int(0)),
            (.int(-102_500), .int(-102_500)),
            (.double(0.85), .double(0.85)),
            (.string(""), .string("")),
            (.string("wave 3"), .string("wave 3")),
            (.array([]), .array([])),
            (.array([.int(1), .string("two"), .null]), .array([.int(1), .string("two"), .null])),
            (.object([:]), .object([])),
        ]
    )
    func eachCaseRoundTrips(value: PreservedValue, encoded: ProbeValue) throws {
        #expect(try probeEncode(value) == encoded)
        #expect(try probeDecode(PreservedValue.self, from: encoded) == value)
    }

    @Test("A whole number stays an integer rather than becoming a double")
    func integersAreTriedBeforeDoubles() throws {
        // `int` before `double` in the decoder, so a value written as 5 comes back as 5 and not 5.0.
        // The reverse is not true and cannot be: a JSON 5.0 has no integer marker to preserve.
        #expect(try probeDecode(PreservedValue.self, from: .int(5)) == .int(5))
        #expect(try probeDecode(PreservedValue.self, from: .double(5)) == .double(5))
    }

    @Test("Nesting survives to any depth the payload uses")
    func nestingSurvives() throws {
        let nested = PreservedValue.object([
            "steps": .array([.object(["percent": .double(0.7)]), .object(["percent": .double(0.8)])])
        ])
        #expect(try probeDecode(PreservedValue.self, from: try probeEncode(nested)) == nested)
    }

    @Test("A key is its spelling and never an index")
    func aKeyIsAlwaysAString() {
        // `AnyCodingKey` exists because a payload's keys are not known at compile time. An integer
        // key has no meaning in any format this module writes, so it is refused rather than
        // stringified — which would let `0` and `"0"` name the same field.
        #expect(AnyCodingKey(intValue: 3) == nil)
        #expect(AnyCodingKey("base").intValue == nil)
        #expect(AnyCodingKey(stringValue: "base")?.stringValue == "base")
    }

    @Test("Object keys are written sorted")
    func objectKeysAreSorted() throws {
        let value = PreservedValue.object(["cap": .int(2), "base": .int(1), "wave": .int(3)])
        #expect(
            try probeEncode(value)
                == .object([
                    ProbeField(key: "base", value: .int(1)),
                    ProbeField(key: "cap", value: .int(2)),
                    ProbeField(key: "wave", value: .int(3)),
                ]))
    }
}
