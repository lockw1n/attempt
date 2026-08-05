import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).

/// Builds a set, failing the test rather than force unwrapping (`force_unwrapping` is banned by
/// `.swiftlint.yml`). Same shape as `RoundingRuleTests.roundingRule`.
///
/// The defaults are a *working, completed* set of five reps at 100 kg — the case most tests want
/// as a baseline. `isWarmup` and `isCompleted` have no defaults on the type itself (`G-1.8`); they
/// have them here because a test helper is not a call site that can lose them.
func setRecord(
    weight: Weight = Weight(grams: 100_000),
    reps: Int = 5,
    rpe: Double? = nil,
    rir: Int? = nil,
    isWarmup: Bool = false,
    isCompleted: Bool = true,
    modifiers: [SetModifier] = []
) throws -> SetRecord {
    try #require(
        SetRecord(
            weight: weight,
            reps: reps,
            rpe: rpe,
            rir: rir,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            modifiers: modifiers))
}

@Suite("SetRecord — construction")
struct SetRecordConstructionTests {
    @Test("All seven TR-0.2.3 fields are stored as given")
    func allFieldsAreStored() throws {
        let record = try setRecord(
            weight: Weight(grams: 102_500),
            reps: 3,
            rpe: 8.5,
            rir: 1,
            isWarmup: true,
            isCompleted: false,
            modifiers: [SetModifier(.belt)])
        #expect(record.weight == Weight(grams: 102_500))
        #expect(record.reps == 3)
        #expect(record.rpe == 8.5)
        #expect(record.rir == 1)
        #expect(record.isWarmup)
        #expect(!record.isCompleted)
        #expect(record.modifiers == [SetModifier(.belt)])
    }

    @Test("RPE, RIR and modifiers are optional at the call site; the two flags are not")
    func onlyTheOptionalFieldsHaveDefaults() throws {
        // G-1.8 in code: this compiles only because `isWarmup` and `isCompleted` are passed. If
        // they ever acquire defaults, a call site can silently log a warmup as working, and the
        // value cannot be recovered afterwards.
        let record = try #require(
            SetRecord(weight: Weight(grams: 60_000), reps: 10, isWarmup: false, isCompleted: true))
        #expect(record.rpe == nil)
        #expect(record.rir == nil)
        #expect(record.modifiers.isEmpty)
    }

    @Test("Two records with the same fields are equal")
    func equalityCoversEveryField() throws {
        let belt = [SetModifier(.belt)]
        let base = try setRecord(rpe: 8, rir: 2, modifiers: belt)
        #expect(base == (try setRecord(rpe: 8, rir: 2, modifiers: belt)))
        #expect(base != (try setRecord(weight: Weight(grams: 100_001), rpe: 8, rir: 2, modifiers: belt)))
        #expect(base != (try setRecord(reps: 6, rpe: 8, rir: 2, modifiers: belt)))
        #expect(base != (try setRecord(rpe: 9, rir: 2, modifiers: belt)))
        #expect(base != (try setRecord(rpe: 8, rir: 3, modifiers: belt)))
        #expect(base != (try setRecord(rpe: 8, rir: 2, isWarmup: true, modifiers: belt)))
        #expect(base != (try setRecord(rpe: 8, rir: 2, isCompleted: false, modifiers: belt)))
        #expect(base != (try setRecord(rpe: 8, rir: 2, modifiers: [])))
    }
}

@Suite("SetRecord — reps and weight ranges")
struct SetRecordRepsAndWeightTests {
    @Test("Zero reps is legal — a failed set records what was actually achieved")
    func zeroRepsIsAccepted() throws {
        // FR-1.2.5. A failed set with no reps is a real logging outcome, not corruption.
        let record = try setRecord(reps: 0, isCompleted: false)
        #expect(record.reps == 0)
    }

    @Test("A negative rep count is rejected", arguments: [-1, -5, Int.min])
    func negativeRepsAreRejected(reps: Int) {
        #expect(SetRecord(weight: .zero, reps: reps, isWarmup: false, isCompleted: true) == nil)
    }

    @Test("A negative weight is accepted — assisted bodyweight work")
    func negativeWeightIsAccepted() throws {
        // A band- or machine-assisted pull-up is genuinely a negative *added* load. `Weight` is
        // signed and this type does not narrow it; enforcing non-negativity would make assisted
        // work unloggable.
        let record = try setRecord(weight: Weight(grams: -20_000), reps: 8)
        #expect(record.weight == Weight(grams: -20_000))
    }

    @Test("The weight is stored exactly as given — nothing doubles or normalises it")
    func weightIsStoredUnmodified() throws {
        // The mechanical half of T-0.12's per-implement decision, and the only half a test can
        // hold. "40 means one 40 kg dumbbell, not the pair" is a contract about what the number
        // *means*; no assertion can distinguish it from the other convention, because both store
        // 40. What is testable is that nothing here rewrites the number on its way in — which is
        // what a "pair" convention would have had to do, and what `G-1.6` forbids for logged data.
        // The meaning itself lives in `SetRecord.weight`'s doc comment; it is documentation, and
        // this comment exists so nobody mistakes the assertion below for proof of it.
        for grams in [40_000, 100_000, 0, -20_000, 1] {
            #expect(try setRecord(weight: Weight(grams: grams), reps: 10).weight == Weight(grams: grams))
        }
    }
}

@Suite("SetRecord — RPE and RIR")
struct SetRecordEffortTests {
    // The "done when" asks for the ranges to be documented and either enforced or explicitly
    // tolerated, with a test proving which. The answer is split on purpose: the 1–10 *bound* is
    // enforced because the scale is defined that way, and the 0.5 *step* is tolerated because it
    // is a UI convention and rejecting a finer value from a newer version would cost the whole
    // record.

    @Test("The documented ranges are the ones enforced")
    func rangesAreWhatTheDocsSay() {
        #expect(SetRecord.rpeRange == 1...10)
        #expect(SetRecord.rirRange == 0...9)
        #expect(SetRecord.repsRange == 0...Int.max)
    }

    @Test("RPE at and inside the bounds is accepted", arguments: [1.0, 6.0, 8.5, 9.5, 10.0])
    func rpeInRangeIsAccepted(rpe: Double) throws {
        #expect(try setRecord(rpe: rpe).rpe == rpe)
    }

    @Test("RPE outside the bounds is rejected", arguments: [0.9, 0.0, -1.0, 10.1, 47.0])
    func rpeOutOfRangeIsRejected(rpe: Double) {
        #expect(SetRecord(weight: .zero, reps: 1, rpe: rpe, isWarmup: false, isCompleted: true) == nil)
    }

    @Test("A non-finite RPE is rejected")
    func nonFiniteRPEIsRejected() {
        // Also what keeps `Hashable` well-behaved: a stored NaN would make a record unequal to
        // itself. The range check does this for free — every comparison against NaN is false.
        #expect(SetRecord(weight: .zero, reps: 1, rpe: .nan, isWarmup: false, isCompleted: true) == nil)
        #expect(SetRecord(weight: .zero, reps: 1, rpe: .infinity, isWarmup: false, isCompleted: true) == nil)
        #expect(SetRecord(weight: .zero, reps: 1, rpe: -.infinity, isWarmup: false, isCompleted: true) == nil)
    }

    @Test("An RPE off the conventional half-point step is tolerated", arguments: [8.25, 7.1, 9.75])
    func offStepRPEIsTolerated(rpe: Double) throws {
        // Explicitly tolerated, not overlooked. The step is what the UI offers; the bound is what
        // the scale means. Rejecting 8.25 from a newer version would lose the set, not the field.
        #expect(try setRecord(rpe: rpe).rpe == rpe)
    }

    @Test("RIR at and inside the bounds is accepted", arguments: [0, 1, 5, 9])
    func rirInRangeIsAccepted(rir: Int) throws {
        #expect(try setRecord(rir: rir).rir == rir)
    }

    @Test("RIR outside the bounds is rejected", arguments: [-1, 10, Int.max, Int.min])
    func rirOutOfRangeIsRejected(rir: Int) {
        #expect(SetRecord(weight: .zero, reps: 1, rir: rir, isWarmup: false, isCompleted: true) == nil)
    }

    @Test("Both may be set at once, and they are not required to agree")
    func rpeAndRirAreIndependent() throws {
        // They encode the same information two ways (`rir = 10 - rpe`), but TR-0.2.3 and TR-0.3.4
        // both list them as independent optional fields, and G-1.6 forbids the app rewriting one
        // to match the other. Which wins when they disagree belongs to the RPE formula (T-0.15).
        let agreeing = try setRecord(rpe: 9, rir: 1)
        #expect(agreeing.rpe == 9 && agreeing.rir == 1)
        let contradicting = try setRecord(rpe: 9, rir: 5)
        #expect(contradicting.rpe == 9 && contradicting.rir == 5)
    }
}

@Suite("SetRecord — modifiers")
struct SetRecordModifierTests {
    @Test("Duplicates are removed")
    func duplicatesAreRemoved() throws {
        let record = try setRecord(modifiers: [SetModifier(.belt), SetModifier(.belt)])
        #expect(record.modifiers == [SetModifier(.belt)])
    }

    @Test("Order is canonical, so two orderings produce the same record")
    func orderIsCanonical() throws {
        // The reason `modifiers` is a canonicalised Array rather than a Set: a Set iterates
        // nondeterministically and could not be pinned on the wire, while a raw Array would make
        // belt+sleeves a different record from sleeves+belt.
        let one = try setRecord(modifiers: [SetModifier(.sleeves), SetModifier(.belt)])
        let other = try setRecord(modifiers: [SetModifier(.belt), SetModifier(.sleeves)])
        #expect(one == other)
        #expect(one.modifiers == [SetModifier(.belt), SetModifier(.sleeves)])
    }

    @Test("The canonical order is by raw spelling, and unknown terms sort with the rest")
    func canonicalOrderIsByRawSpelling() throws {
        let record = try setRecord(modifiers: [
            SetModifier(.wraps), SetModifier(rawValue: "chains"), SetModifier(.belt),
        ])
        #expect(record.modifiers.map(\.rawValue) == ["belt", "chains", "wraps"])
    }

    @Test("An unrecognised modifier is kept, not dropped")
    func unknownModifierIsKept() throws {
        let record = try setRecord(modifiers: [SetModifier(rawValue: "chains")])
        #expect(record.modifiers.map(\.rawValue) == ["chains"])
    }

    @Test("No modifiers is the empty array, not nil")
    func noModifiersIsEmpty() throws {
        #expect(try setRecord().modifiers.isEmpty)
    }
}

@Suite("SetRecord — wire format")
struct SetRecordCodableTests {
    // Follows RoundingRule's precedent: one ordered-object assertion pins key spelling, key order
    // and the fact that nested values keep their own shapes — `weight` a bare integer of grams,
    // each modifier a bare string.

    private let fullShape = ProbeValue.object([
        ProbeField(key: "weight", value: .int(102_500)),
        ProbeField(key: "reps", value: .int(3)),
        ProbeField(key: "rpe", value: .double(8.5)),
        ProbeField(key: "rir", value: .int(1)),
        ProbeField(key: "isWarmup", value: .bool(false)),
        ProbeField(key: "isCompleted", value: .bool(true)),
        ProbeField(key: "modifiers", value: .array([.string("belt"), .string("sleeves")])),
    ])

    private func fullRecord() throws -> SetRecord {
        try setRecord(
            weight: Weight(grams: 102_500),
            reps: 3,
            rpe: 8.5,
            rir: 1,
            isWarmup: false,
            isCompleted: true,
            modifiers: [SetModifier(.sleeves), SetModifier(.belt)])
    }

    @Test("Encodes as a seven-key object in the pinned order")
    func encodesAsPinnedObject() throws {
        #expect(try probeEncode(try fullRecord()) == fullShape)
    }

    @Test("Absent RPE and RIR are omitted rather than written as null")
    func absentOptionalsAreOmitted() throws {
        let record = try setRecord(weight: Weight(grams: 60_000), reps: 10, isWarmup: true, isCompleted: false)
        #expect(
            try probeEncode(record)
                == .object([
                    ProbeField(key: "weight", value: .int(60_000)),
                    ProbeField(key: "reps", value: .int(10)),
                    ProbeField(key: "isWarmup", value: .bool(true)),
                    ProbeField(key: "isCompleted", value: .bool(false)),
                    ProbeField(key: "modifiers", value: .array([])),
                ]))
    }

    @Test("Round-trips through Codable")
    func roundTripsThroughCodable() throws {
        let records = [
            try fullRecord(),
            try setRecord(weight: Weight(grams: -20_000), reps: 0, isWarmup: true, isCompleted: false),
            try setRecord(rpe: 10, modifiers: [SetModifier(rawValue: "chains")]),
            try setRecord(rir: 0),
        ]
        for record in records {
            #expect(try probeDecode(SetRecord.self, from: try probeEncode(record)) == record)
        }
    }

    @Test("Encode → decode → encode is byte-stable")
    func encodingIsStableAcrossARoundTrip() throws {
        let first = try probeEncode(try fullRecord())
        let second = try probeEncode(try probeDecode(SetRecord.self, from: first))
        #expect(first == second)
    }

    @Test("Decoding accepts the keys in any order and re-encodes in the pinned one")
    func decodingIsOrderInsensitive() throws {
        let reordered = ProbeValue.object([
            ProbeField(key: "modifiers", value: .array([.string("belt"), .string("sleeves")])),
            ProbeField(key: "isCompleted", value: .bool(true)),
            ProbeField(key: "rir", value: .int(1)),
            ProbeField(key: "isWarmup", value: .bool(false)),
            ProbeField(key: "rpe", value: .double(8.5)),
            ProbeField(key: "reps", value: .int(3)),
            ProbeField(key: "weight", value: .int(102_500)),
        ])
        #expect(try probeDecode(SetRecord.self, from: reordered) == (try fullRecord()))
        #expect(try probeEncode(try probeDecode(SetRecord.self, from: reordered)) == fullShape)
    }

    @Test("An explicit null decodes as an absent RPE or RIR")
    func explicitNullIsAcceptedForOptionals() throws {
        let withNulls = ProbeValue.object([
            ProbeField(key: "weight", value: .int(60_000)),
            ProbeField(key: "reps", value: .int(10)),
            ProbeField(key: "rpe", value: .null),
            ProbeField(key: "rir", value: .null),
            ProbeField(key: "isWarmup", value: .bool(false)),
            ProbeField(key: "isCompleted", value: .bool(true)),
            ProbeField(key: "modifiers", value: .array([])),
        ])
        let decoded = try probeDecode(SetRecord.self, from: withNulls)
        #expect(decoded.rpe == nil)
        #expect(decoded.rir == nil)
        // Both forms decode; only the omission is ever produced.
        #expect(try probeEncode(decoded) == (try probeEncode(try setRecord(weight: Weight(grams: 60_000), reps: 10))))
    }

    @Test("A modifier collection decodes in canonical order whatever order it arrives in")
    func decodedModifiersAreCanonicalised() throws {
        let unordered = ProbeValue.object([
            ProbeField(key: "weight", value: .int(60_000)),
            ProbeField(key: "reps", value: .int(10)),
            ProbeField(key: "isWarmup", value: .bool(false)),
            ProbeField(key: "isCompleted", value: .bool(true)),
            ProbeField(
                key: "modifiers",
                value: .array([.string("wraps"), .string("belt"), .string("wraps")])),
        ])
        let decoded = try probeDecode(SetRecord.self, from: unordered)
        #expect(decoded.modifiers.map(\.rawValue) == ["belt", "wraps"])
    }

    @Test("An unrecognised modifier decodes without throwing and survives re-encoding")
    func unknownModifierSurvivesDecoding() throws {
        // The task's headline criterion: "modifiers round-trip through Codable with an unknown
        // modifier preserved, not dropped".
        let future = ProbeValue.object([
            ProbeField(key: "weight", value: .int(60_000)),
            ProbeField(key: "reps", value: .int(10)),
            ProbeField(key: "isWarmup", value: .bool(false)),
            ProbeField(key: "isCompleted", value: .bool(true)),
            ProbeField(key: "modifiers", value: .array([.string("belt"), .string("chains")])),
        ])
        let decoded = try probeDecode(SetRecord.self, from: future)
        #expect(decoded.modifiers.map(\.rawValue) == ["belt", "chains"])
        #expect(decoded.modifiers.map(\.known) == [.belt, nil])
        #expect(try probeEncode(decoded) == future)
    }

    @Test("Decoding enforces the rep range", arguments: [-1, Int.min])
    func decodingEnforcesTheRepRange(reps: Int) {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(SetRecord.self, from: Self.payload(reps: .int(reps)))
        }
    }

    @Test("Decoding enforces the RPE range", arguments: [0.9, 10.1, Double.nan])
    func decodingEnforcesTheRPERange(rpe: Double) {
        // The point of hand-writing `init(from:)`: synthesised `Decodable` bypasses the failable
        // initialiser and would hand every formula downstream an RPE of 47 to defend against.
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(SetRecord.self, from: Self.payload(rpe: .double(rpe)))
        }
    }

    @Test("Decoding enforces the RIR range", arguments: [-1, 10])
    func decodingEnforcesTheRIRRange(rir: Int) {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(SetRecord.self, from: Self.payload(rir: .int(rir)))
        }
    }

    @Test("A missing key throws")
    func missingKeyThrows() {
        // Including the two G-1.8 flags: they are non-optional on the wire as well as in memory,
        // so a payload without them is corrupt rather than a set that defaults to "working".
        for missing in ["weight", "reps", "isWarmup", "isCompleted", "modifiers"] {
            let truncated = ProbeValue.object(
                Self.payloadFields().filter { $0.key != missing })
            #expect(throws: DecodingError.self) {
                _ = try probeDecode(SetRecord.self, from: truncated)
            }
        }
    }

    @Test("A non-object throws")
    func nonObjectThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(SetRecord.self, from: .int(102_500))
        }
    }

    @Test("A non-array modifiers value throws")
    func nonArrayModifiersThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(SetRecord.self, from: Self.payload(modifiers: .string("belt")))
        }
    }

    /// A valid payload with one field swapped out, so each assertion above says what it varies.
    private static func payload(
        reps: ProbeValue = .int(5),
        rpe: ProbeValue? = nil,
        rir: ProbeValue? = nil,
        modifiers: ProbeValue = .array([])
    ) -> ProbeValue {
        var fields = [
            ProbeField(key: "weight", value: .int(100_000)),
            ProbeField(key: "reps", value: reps),
        ]
        if let rpe { fields.append(ProbeField(key: "rpe", value: rpe)) }
        if let rir { fields.append(ProbeField(key: "rir", value: rir)) }
        fields.append(ProbeField(key: "isWarmup", value: .bool(false)))
        fields.append(ProbeField(key: "isCompleted", value: .bool(true)))
        fields.append(ProbeField(key: "modifiers", value: modifiers))
        return .object(fields)
    }

    private static func payloadFields() -> [ProbeField] {
        guard case .object(let fields) = payload() else { return [] }
        return fields
    }
}
