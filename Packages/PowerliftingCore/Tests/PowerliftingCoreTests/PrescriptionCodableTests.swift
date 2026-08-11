import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// These are T-0.20's golden fixtures, expressed as `ProbeValue` trees rather than as committed JSON
// text. That is a deliberate trade and it is the weaker half of one: a tree pins key spelling, key
// order and the shape of every nested value, but nothing here proves what bytes Foundation's
// `JSONEncoder` would emit for the same value. It cannot — `NFR-0.2` keeps Foundation out of this
// package, and `OUT-0.3` means Phase 0 has no real encoder to pin anyway, since the blob TR-2.1
// persists arrives in Phase 2. The byte-level fixture is owed there, against `TR-2.1`/`TR-2.7`.

/// `{"version": …, "type": …, <payload>}` — the envelope every prescription shares.
///
/// The envelope's two keys are written in this order, before any payload key.
/// ``fixedWeightIsWrittenOutInFull`` spells one whole fixture out literally so this helper cannot
/// drift without something failing.
func encodedPrescription(
    _ type: String, _ payload: [(String, ProbeValue)] = [], version: Int = 1
) -> ProbeValue {
    .object(
        [ProbeField(key: "version", value: .int(version)), ProbeField(key: "type", value: .string(type))]
            + payload.map { ProbeField(key: $0.0, value: $0.1) })
}

/// Every case of `TR-0.2.10` with the shape it is pinned to.
///
/// A nested `Weight` is a bare integer of grams — 102500, not `{"grams": 102500}` — which is
/// `Weight`'s own pinned format and a storage contract in its own right.
let prescriptionFixtures: [(prescription: Prescription, encoded: ProbeValue)] = [
    (.fixedWeight(Weight(grams: 102_500)), encodedPrescription("fixedWeight", [("weight", .int(102_500))])),
    (
        .percentOfTrainingMax(percentage: 0.85),
        encodedPrescription("percentOfTrainingMax", [("percentage", .double(0.85))])
    ),
    (.percentOfE1RM(percentage: 0.75), encodedPrescription("percentOfE1RM", [("percentage", .double(0.75))])),
    (.percentOfTopSet(percentage: 0.9), encodedPrescription("percentOfTopSet", [("percentage", .double(0.9))])),
    (.rpeTarget(rpe: 8.5), encodedPrescription("rpeTarget", [("rpe", .double(8.5))])),
    (.amrap, encodedPrescription("amrap")),
    (
        .previousPlusIncrement(Weight(grams: 2_500)),
        encodedPrescription("previousPlusIncrement", [("increment", .int(2_500))])
    ),
    (.bodyweight(added: Weight(grams: 20_000)), encodedPrescription("bodyweight", [("added", .int(20_000))])),
]

/// The payload key each case carries, for the tests that remove or corrupt it. `.amrap` has none,
/// which is why it is absent here and asserted separately.
let prescriptionPayloadKeys: [(type: String, key: String)] = [
    ("fixedWeight", "weight"),
    ("percentOfTrainingMax", "percentage"),
    ("percentOfE1RM", "percentage"),
    ("percentOfTopSet", "percentage"),
    ("rpeTarget", "rpe"),
    ("previousPlusIncrement", "increment"),
    ("bodyweight", "added"),
]

@Suite("Prescription — the pinned wire format")
struct PrescriptionWireFormatTests {
    @Test("Every case encodes to its pinned shape", arguments: prescriptionFixtures)
    func everyCaseEncodesToItsPinnedShape(prescription: Prescription, encoded: ProbeValue) throws {
        #expect(try probeEncode(prescription) == encoded)
    }

    @Test("Every case decodes from its pinned shape", arguments: prescriptionFixtures)
    func everyCaseDecodesFromItsPinnedShape(prescription: Prescription, encoded: ProbeValue) throws {
        #expect(try probeDecode(Prescription.self, from: encoded) == prescription)
    }

    @Test("Encode → decode → encode is byte-stable", arguments: prescriptionFixtures)
    func everyCaseIsStableAcrossARoundTrip(prescription: Prescription, encoded: ProbeValue) throws {
        let first = try probeEncode(prescription)
        let second = try probeEncode(try probeDecode(Prescription.self, from: first))
        #expect(first == second)
    }

    @Test("One fixture written out in full, so the helper above cannot drift")
    func fixedWeightIsWrittenOutInFull() throws {
        #expect(
            try probeEncode(Prescription.fixedWeight(Weight(grams: 102_500)))
                == .object([
                    ProbeField(key: "version", value: .int(1)),
                    ProbeField(key: "type", value: .string("fixedWeight")),
                    ProbeField(key: "weight", value: .int(102_500)),
                ]))
    }

    @Test("AMRAP is the envelope and nothing else")
    func amrapCarriesNoPayload() throws {
        // The case that carries no load, because reps belong to the slot (FR-2.2.2). If this ever
        // grows a key, the wire format stays compatible only if that key is optional.
        guard case .object(let fields) = try probeEncode(Prescription.amrap) else {
            Issue.record("AMRAP did not encode as an object")
            return
        }
        #expect(fields.map(\.key) == ["version", "type"])
    }

    @Test("Decoding accepts the keys in any order and re-encodes in the pinned one")
    func decodingIsOrderInsensitive() throws {
        let reordered = ProbeValue.object([
            ProbeField(key: "weight", value: .int(102_500)),
            ProbeField(key: "type", value: .string("fixedWeight")),
            ProbeField(key: "version", value: .int(1)),
        ])
        let decoded = try probeDecode(Prescription.self, from: reordered)
        #expect(decoded == .fixedWeight(Weight(grams: 102_500)))
        #expect(try probeEncode(decoded) == encodedPrescription("fixedWeight", [("weight", .int(102_500))]))
    }
}

@Suite("Prescription — what the decoder refuses")
struct PrescriptionDecodingRefusalTests {
    // Tolerance is for a newer vocabulary, never for a broken payload. An unrecognised `type` is
    // preserved (see the forward-compatibility suite); everything below is corruption.

    @Test("A known type missing its payload key throws", arguments: prescriptionPayloadKeys)
    func aMissingPayloadKeyThrows(type: String, key: String) {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Prescription.self, from: encodedPrescription(type))
        }
    }

    @Test("A known type with a mistyped payload value throws", arguments: prescriptionPayloadKeys)
    func aMistypedPayloadValueThrows(type: String, key: String) {
        let corrupt = encodedPrescription(type, [(key, .string("heavy"))])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Prescription.self, from: corrupt)
        }
    }

    @Test("A missing version throws")
    func aMissingVersionThrows() {
        let noVersion = ProbeValue.object([
            ProbeField(key: "type", value: .string("fixedWeight")),
            ProbeField(key: "weight", value: .int(102_500)),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Prescription.self, from: noVersion)
        }
    }

    @Test("A missing type throws")
    func aMissingTypeThrows() {
        let noType = ProbeValue.object([
            ProbeField(key: "version", value: .int(1)),
            ProbeField(key: "weight", value: .int(102_500)),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Prescription.self, from: noType)
        }
    }

    @Test("A version below one throws", arguments: [0, -1, Int.min])
    func aVersionBelowOneThrows(version: Int) {
        // Zero is not "unversioned": TR-2.4 makes the version part of what identifies the blob, and
        // a value that cannot have been written by any version of this app is corruption.
        let corrupt = encodedPrescription("fixedWeight", [("weight", .int(102_500))], version: version)
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Prescription.self, from: corrupt)
        }
    }

    @Test("A non-integer version throws")
    func aNonIntegerVersionThrows() {
        let corrupt = ProbeValue.object([
            ProbeField(key: "version", value: .string("1")),
            ProbeField(key: "type", value: .string("fixedWeight")),
            ProbeField(key: "weight", value: .int(102_500)),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Prescription.self, from: corrupt)
        }
    }

    @Test("A non-string type throws")
    func aNonStringTypeThrows() {
        let corrupt = ProbeValue.object([
            ProbeField(key: "version", value: .int(1)),
            ProbeField(key: "type", value: .int(3)),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Prescription.self, from: corrupt)
        }
    }

    @Test("A non-object throws", arguments: [ProbeValue.int(1), .string("fixedWeight"), .null, .array([])])
    func aNonObjectThrows(value: ProbeValue) {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Prescription.self, from: value)
        }
    }
}
