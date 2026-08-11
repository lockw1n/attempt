import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).

@Suite("Prescription — the recognised vocabulary")
struct PrescriptionKindTests {
    @Test(
        "Raw values are the persisted spelling",
        arguments: [
            (PrescriptionKind.fixedWeight, "fixedWeight"),
            (.percentOfTrainingMax, "percentOfTrainingMax"),
            (.percentOfE1RM, "percentOfE1RM"),
            (.percentOfTopSet, "percentOfTopSet"),
            (.rpeTarget, "rpeTarget"),
            (.amrap, "amrap"),
            (.previousPlusIncrement, "previousPlusIncrement"),
            (.bodyweight, "bodyweight"),
        ]
    )
    func rawValuesAreThePersistedSpelling(kind: PrescriptionKind, spelling: String) {
        // Asserted against literals rather than through `rawValue`, which would only prove the enum
        // agrees with itself. Renaming one of these is a storage migration.
        #expect(kind.rawValue == spelling)
    }

    @Test("TR-0.2.10's eight types are all of them")
    func theVocabularyIsTheRequiredOne() {
        #expect(PrescriptionKind.allCases.count == 8)
    }

    @Test("The fixtures cover all eight types, each exactly once")
    func theFixturesCoverEveryType() {
        // The anchor for every fixture-driven test in the wire-format suite: those are
        // parameterized over `prescriptionFixtures`, so a fixture quietly dropped would take its
        // assertions with it and the suite would stay green. Compared as a set, so two fixtures for
        // one type cannot stand in for a missing one.
        #expect(Set(prescriptionFixtures.compactMap(\.prescription.kind)) == Set(PrescriptionKind.allCases))
        #expect(prescriptionFixtures.count == PrescriptionKind.allCases.count)
    }

    @Test("Every case but the preserved one carries a discriminator")
    func everyRecognisedCaseHasAKind() {
        for (prescription, encoded) in prescriptionFixtures {
            guard case .object(let fields) = encoded,
                let type = fields.first(where: { $0.key == "type" }),
                case .string(let spelling) = type.value
            else {
                Issue.record("Fixture \(prescription) has no string type key")
                continue
            }
            #expect(prescription.kind?.rawValue == spelling)
            #expect(prescription.isRecognised)
        }
    }

    @Test("A preserved prescription is the only unrecognised value")
    func onlyThePreservedCaseIsUnrecognised() throws {
        let preserved = try #require(UnrecognisedPrescription(kind: "wavePercent", schemaVersion: 2))
        #expect(Prescription.unrecognised(preserved).isRecognised == false)
        #expect(Prescription.unrecognised(preserved).kind == nil)
    }
}

@Suite("Prescription — the preserved case cannot shadow a known one")
struct UnrecognisedPrescriptionTests {
    // The injectivity guard. Without it, `.unrecognised(kind: "fixedWeight", …)` would encode
    // identically to `.fixedWeight(…)` while comparing unequal and hashing differently — the same
    // failure that made `OpenVocabulary` a struct rather than a `known`/`unknown` enum.

    @Test("A recognised spelling is refused", arguments: PrescriptionKind.allCases)
    func aRecognisedKindIsRefused(kind: PrescriptionKind) {
        #expect(UnrecognisedPrescription(kind: kind.rawValue, schemaVersion: 1) == nil)
    }

    @Test("An unrecognised spelling is accepted", arguments: ["wavePercent", "", "FixedWeight", "fixedweight"])
    func anUnrecognisedKindIsAccepted(kind: String) throws {
        // Case matters: `FixedWeight` is not `fixedWeight`, and the empty string is a spelling like
        // any other. Nothing is normalised, for the reason `OpenVocabulary` normalises nothing —
        // rewriting a value the app cannot interpret is exactly what G-1.6 forbids.
        let preserved = try #require(UnrecognisedPrescription(kind: kind, schemaVersion: 1))
        #expect(preserved.kind == kind)
    }

    @Test("A schema version below one is refused", arguments: [0, -1, Int.min])
    func aVersionBelowOneIsRefused(version: Int) {
        #expect(UnrecognisedPrescription(kind: "wavePercent", schemaVersion: version) == nil)
    }

    @Test("A version at or above one is accepted", arguments: [1, 2, Int.max])
    func aVersionOfAtLeastOneIsAccepted(version: Int) throws {
        let preserved = try #require(UnrecognisedPrescription(kind: "wavePercent", schemaVersion: version))
        #expect(preserved.schemaVersion == version)
    }

    @Test("The payload defaults to empty and is kept as given")
    func thePayloadIsKeptAsGiven() throws {
        #expect(try #require(UnrecognisedPrescription(kind: "wavePercent", schemaVersion: 2)).payload.isEmpty)
        let carried = try #require(
            UnrecognisedPrescription(
                kind: "wavePercent", schemaVersion: 2, payload: ["wave": .int(3), "base": .double(0.7)]))
        #expect(carried.payload == ["wave": .int(3), "base": .double(0.7)])
    }

    @Test("A payload carrying an envelope key is refused", arguments: ["type", "version"])
    func aPayloadMayNotShadowTheEnvelope(key: String) {
        // The second way to shadow a known type, and the decoder cannot produce it — only a caller
        // building one by hand. Measured before it was closed: a payload `"type": "fixedWeight"`
        // encoded to an object with **two** `type` keys, and which one wins is the encoder's
        // business. Through this module's probe the envelope's won and the payload key vanished on
        // the way back — so encode → decode → encode was not stable. Through a dictionary-backed
        // encoder such as `JSONEncoder` the payload's wins instead, and the blob decodes as
        // `.fixedWeight(102.5 kg)`: a different prescription, silently.
        let payload: [String: PreservedValue] = [key: .string("fixedWeight"), "base": .double(0.7)]
        #expect(UnrecognisedPrescription(kind: "wavePercent", schemaVersion: 2, payload: payload) == nil)
    }
}

@Suite("Prescription — value semantics")
struct PrescriptionValueSemanticsTests {
    @Test("The current schema version is one")
    func currentSchemaVersionIsOne() {
        #expect(Prescription.currentSchemaVersion == 1)
    }

    @Test("Equal payloads compare equal, different ones do not")
    func equalityCoversThePayload() {
        #expect(Prescription.fixedWeight(Weight(grams: 100_000)) == .fixedWeight(Weight(grams: 100_000)))
        #expect(Prescription.fixedWeight(Weight(grams: 100_000)) != .fixedWeight(Weight(grams: 100_001)))
        #expect(Prescription.percentOfE1RM(percentage: 0.85) != .percentOfTrainingMax(percentage: 0.85))
        #expect(Prescription.amrap == .amrap)
        #expect(Prescription.bodyweight(added: .zero) != .fixedWeight(.zero))
    }

    @Test("Nothing is validated at construction")
    func nothingIsValidatedAtConstruction() {
        // Percentages and RPEs that no resolution can use are still constructible: an enum case
        // cannot be failable, and refusing them is TR-0.2.11's job, where the caller can be told
        // which input was impossible. Deleting these assertions would not fail anything — they are
        // here so that adding validation later has to be a decision.
        #expect(Prescription.percentOfTrainingMax(percentage: 0) == .percentOfTrainingMax(percentage: 0))
        #expect(Prescription.percentOfE1RM(percentage: -1) == .percentOfE1RM(percentage: -1))
        #expect(Prescription.rpeTarget(rpe: 47) == .rpeTarget(rpe: 47))
        #expect(Prescription.rpeTarget(rpe: 8.25) == .rpeTarget(rpe: 8.25))
    }

    @Test("A NaN percentage does not equal itself")
    func aNaNPercentageDoesNotEqualItself() {
        // A recorded property, not a design goal. `SetRecord` rejects NaN in its initialiser; an
        // enum case has no initialiser to reject it in, so `Double`'s equality shows through.
        #expect(Prescription.percentOfTrainingMax(percentage: .nan) != .percentOfTrainingMax(percentage: .nan))
    }

    @Test("Negative weights are accepted where they mean something")
    func negativeWeightsAreAccepted() {
        // Assistance on bodyweight work, and a configured deload as a progression step. Both match
        // decisions made one type over: SetRecord.weight may be negative, and a training max's
        // progression increment may be too.
        #expect(Prescription.bodyweight(added: Weight(grams: -20_000)) != .bodyweight(added: Weight(grams: 20_000)))
        #expect(
            Prescription.previousPlusIncrement(Weight(grams: -2_500))
                != .previousPlusIncrement(Weight(grams: 2_500)))
    }
}
