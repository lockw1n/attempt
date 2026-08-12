import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@Suite("EquipmentProfile → PlateInventory")
struct PlateInventoryProjectionTests {
    private func profile(_ plates: [Int], _ pairs: [Int]) -> EquipmentProfile {
        codingEquipmentProfile(plates: plates.map(Weight.init(grams:)), platePairCounts: pairs)
    }

    @Test("A well-formed profile projects, normalised heaviest first")
    func wellFormedProfileProjects() throws {
        let inventory = try profile([15_000, 25_000], [3, 2]).inventory()

        #expect(inventory.entries.map(\.plate.grams) == [25_000, 15_000])
        #expect(inventory.entries.map(\.pairs) == [2, 3])
    }

    // Every refusal names the offending value, because the caller these exist for is a repair.
    // Asserting only "it threw" would pass for an error that says nothing a user can act on.
    @Test("Lists of different lengths are refused, with both lengths")
    func mismatchedLengthsRefuse() {
        #expect(
            throws: RecordProjectionError.plateListsDisagreeInLength(
                recordID: codingID, plates: 2, pairCounts: 1)
        ) {
            try profile([25_000, 15_000], [2]).inventory()
        }
    }

    @Test("A denomination lighter than one gram is refused, and named")
    func subGramPlateRefuses() {
        #expect(
            throws: RecordProjectionError.plateUnderOneGram(
                recordID: codingID, plate: Weight(grams: 0))
        ) {
            try profile([25_000, 0], [2, 1]).inventory()
        }
    }

    @Test("A negative pair count is refused, and named")
    func negativePairsRefuse() {
        #expect(
            throws: RecordProjectionError.negativePlatePairCount(
                recordID: codingID, plate: Weight(grams: 15_000), pairs: -1)
        ) {
            try profile([25_000, 15_000], [2, -1]).inventory()
        }
    }

    // Refused rather than summed: two entries for 25 kg is far more likely a duplicated row than a
    // statement about two sets of 25s.
    @Test("A repeated denomination is refused, and named")
    func repeatedDenominationRefuses() {
        #expect(
            throws: RecordProjectionError.repeatedPlateDenomination(
                recordID: codingID, plate: Weight(grams: 25_000))
        ) {
            try profile([25_000, 25_000], [2, 1]).inventory()
        }
    }

    // The one refusal left to `PlateInventory` after the three explicit guards, and it is reachable
    // rather than defensive — a plausible denomination and a plausible pair count can still
    // multiply out past `Int`.
    @Test("An inventory whose total overflows Int is refused")
    func overflowingInventoryRefuses() {
        #expect(throws: RecordProjectionError.plateInventoryOverflows(recordID: codingID)) {
            try profile([Int.max / 2, 25_000], [3, 2]).inventory()
        }
    }

    // Zero pairs is legal — a profile may list a denomination the gym currently has none of — and
    // it is the boundary the negative check sits on.
    @Test("Zero pairs of a denomination is not a refusal")
    func zeroPairsIsLegal() throws {
        let inventory = try profile([25_000], [0]).inventory()

        #expect(inventory.entries.map(\.pairs) == [0])
    }
}

@Suite("TrainingMaxEntry → TrainingMaxConfiguration")
struct TrainingMaxProjectionTests {
    private func entry(
        source: TrainingMaxSourceKind,
        sourceRepCount: Int? = 3,
        manualWeight: Weight? = Weight(grams: 180_000),
        percentage: Double = 0.85,
        roundingIncrement: Weight = Weight(grams: 5000)
    ) -> TrainingMaxEntry {
        TrainingMaxEntry(
            id: codingID,
            createdAt: codingCreatedAt,
            updatedAt: codingUpdatedAt,
            deletedAt: nil,
            exerciseID: codingJoinID,
            source: source,
            sourceRepCount: sourceRepCount,
            manualWeight: manualWeight,
            percentage: percentage,
            roundingIncrement: roundingIncrement,
            roundingStrategy: .down,
            progressionIncrement: Weight(grams: 2500),
            effectiveFrom: codingCreatedAt
        )
    }

    @Test("Each of the three sources projects with its own payload")
    func eachSourceProjects() throws {
        #expect(try entry(source: .percentOfE1RM).configuration().source == .percentOfE1RM)
        #expect(
            try entry(source: .percentOfRepMax).configuration().source == .percentOfRepMax(reps: 3))
        #expect(
            try entry(source: .manual).configuration().source == .manual(Weight(grams: 180_000)))
    }

    // The percentage and the rounding rule are carried whatever the source, because a manual
    // training max keeps both as the dormant configuration its one-tap recalculation resumes with.
    // A projection that reset them for a manual row would make FR-1.5.1.5 a one-way door.
    @Test("A manual entry keeps its percentage and rounding rule")
    func manualKeepsItsDormantConfiguration() throws {
        let configuration = try entry(source: .manual).configuration()

        #expect(configuration.percentage == 0.85)
        #expect(configuration.rounding.increment == Weight(grams: 5000))
        #expect(configuration.rounding.strategy == .down)
        #expect(configuration.progressionIncrement == Weight(grams: 2500))
    }

    // What the schema's `.manual` default is chosen to produce: a visible refusal rather than 90%
    // of the user's e1RM handed back as though they had asked for it.
    @Test("A source naming a payload column that is nil is refused, and the source is named")
    func missingPayloadRefuses() {
        #expect(
            throws: RecordProjectionError.trainingMaxPayloadMissing(
                recordID: codingID, source: .manual)
        ) {
            try entry(source: .manual, manualWeight: nil).configuration()
        }
        #expect(
            throws: RecordProjectionError.trainingMaxPayloadMissing(
                recordID: codingID, source: .percentOfRepMax)
        ) {
            try entry(source: .percentOfRepMax, sourceRepCount: nil).configuration()
        }
    }

    // `.percentOfE1RM` reads neither payload column, so a row with both nil still projects — which
    // is what makes the refusal above about the *pairing* rather than about nullability.
    @Test("A percent-of-e1RM entry projects with both payload columns nil")
    func percentOfE1RMNeedsNoPayload() throws {
        let configuration = try entry(
            source: .percentOfE1RM, sourceRepCount: nil, manualWeight: nil
        ).configuration()

        #expect(configuration.source == .percentOfE1RM)
    }

    @Test("A non-positive percentage is refused, and named", arguments: [0.0, -0.5])
    func unusablePercentageRefuses(_ percentage: Double) {
        #expect(
            throws: RecordProjectionError.trainingMaxPercentageUnusable(
                recordID: codingID, percentage: ReportedNumber(percentage))
        ) {
            try entry(source: .percentOfE1RM, percentage: percentage).configuration()
        }
    }

    // NaN has its own test rather than joining the two above, because it is the case the
    // hand-written `==` on `RecordProjectionError` exists for: the synthesised one compares the
    // payload with `Double.==`, which is false for NaN, so this assertion could not have been
    // written in the value form at all. That it now can is the fix working.
    @Test("A non-finite percentage is refused, and named")
    func nonFinitePercentageRefuses() {
        #expect(
            throws: RecordProjectionError.trainingMaxPercentageUnusable(
                recordID: codingID, percentage: .nan)
        ) {
            try entry(source: .percentOfE1RM, percentage: .nan).configuration()
        }
    }

    @Test("An increment below one gram is refused, and named")
    func unloadableIncrementRefuses() {
        #expect(
            throws: RecordProjectionError.roundingIncrementUnloadable(
                recordID: codingID, increment: Weight(grams: 0))
        ) {
            try entry(source: .percentOfE1RM, roundingIncrement: Weight(grams: 0)).configuration()
        }
    }

    // One gram is the identity rule — how a caller asks for no rounding — and the boundary the
    // refusal sits on.
    @Test("A one-gram increment is not a refusal")
    func oneGramIncrementIsLegal() throws {
        let configuration = try entry(
            source: .percentOfE1RM, roundingIncrement: Weight(grams: 1)
        ).configuration()

        #expect(configuration.rounding.increment == Weight(grams: 1))
    }
}

@Suite("UserSettings → RoundingRule")
struct DefaultRoundingProjectionTests {
    // The fourth projection. T-0.40's brief named three; this column is stored unvalidated for the
    // same reason the other three are, so its refusal had nowhere else to live either.
    @Test("The two default-rounding columns project to a rule")
    func settingsProjectToARule() throws {
        let rule = try codingUserSettings().defaultRounding()

        #expect(rule.increment == Weight(grams: 5000))
        #expect(rule.strategy == .down)
    }

    @Test("A default increment below one gram is refused, and named")
    func unloadableDefaultIncrementRefuses() {
        #expect(
            throws: RecordProjectionError.roundingIncrementUnloadable(
                recordID: codingID, increment: Weight(grams: -1))
        ) {
            try codingUserSettings(defaultRoundingIncrement: Weight(grams: -1)).defaultRounding()
        }
    }
}

@Suite("SetEntry → SetRecord")
struct SetRecordProjectionTests {
    @Test("A set projects to the seven fields the formulas read")
    func setProjects() throws {
        let record = try codingSetEntry().setRecord()

        #expect(record.weight == Weight(grams: 142_500))
        #expect(record.reps == 5)
        #expect(record.rpe == 8.5)
        #expect(record.rir == 2)
        #expect(record.isWarmup == true)
        #expect(record.isCompleted == true)
        #expect(record.modifiers.map(\.rawValue) == ["belt", "curriculum"])
    }

    private func set(reps: Int = 5, rpe: Double? = 8.5, rir: Int? = 2) -> SetEntry {
        SetEntry(
            id: codingID,
            createdAt: codingCreatedAt,
            updatedAt: codingUpdatedAt,
            deletedAt: nil,
            entryID: codingJoinID,
            order: 0,
            weight: Weight(grams: 100_000),
            reps: reps,
            rpe: rpe,
            rir: rir,
            isWarmup: false,
            isCompleted: true,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil
        )
    }

    @Test("An RPE outside 1…10 is refused, and named", arguments: [0.5, 10.5])
    func outOfRangeRPERefuses(_ rpe: Double) {
        #expect(throws: RecordProjectionError.rpeOutOfRange(recordID: codingID, rpe: ReportedNumber(rpe))) {
            try set(rpe: rpe).setRecord()
        }
    }

    // NaN falls outside the range and is refused like any other value out of it. Written in the
    // value form on purpose — see `nonFinitePercentageRefuses` for why that is the assertion worth
    // having here.
    @Test("A NaN RPE is refused")
    func nanRPERefuses() {
        #expect(throws: RecordProjectionError.rpeOutOfRange(recordID: codingID, rpe: .nan)) {
            try set(rpe: .nan).setRecord()
        }
    }

    // `SetRecord` refuses three things, not one, and a projection that checked only the RPE would
    // have fallen through to a nil initialiser with no reason to report.
    @Test("A negative rep count is refused, and named")
    func negativeRepsRefuse() {
        #expect(throws: RecordProjectionError.repsOutOfRange(recordID: codingID, reps: -1)) {
            try set(reps: -1).setRecord()
        }
    }

    @Test("An RIR outside 0…9 is refused, and named")
    func outOfRangeRIRRefuses() {
        #expect(throws: RecordProjectionError.rirOutOfRange(recordID: codingID, rir: 10)) {
            try set(rir: 10).setRecord()
        }
    }

    // Zero reps is legal and meaningful — a failed set records the reps actually achieved, which
    // can be none (FR-1.2.5) — and both scales' boundaries are inclusive.
    @Test("The boundaries of all three ranges project")
    func rangeBoundariesProject() throws {
        #expect(try set(reps: 0).setRecord().reps == 0)
        #expect(try set(rpe: 1).setRecord().rpe == 1)
        #expect(try set(rpe: 10).setRecord().rpe == 10)
        #expect(try set(rir: 0).setRecord().rir == 0)
        #expect(try set(rir: 9).setRecord().rir == 9)
    }
}

@Suite("A refusal never costs the record")
struct ProjectionCostTests {
    // The claim T-0.40 §4 shaped the records around, and the one thing a test can add to it that
    // the projections' own suites cannot: the row is still whole after its projection refused. A
    // read that threw instead would have cost the profile its name along with its plates.
    @Test("A profile whose inventory refuses still has its name, bar and collars")
    func refusedProfileIsIntact() {
        let profile = codingEquipmentProfile(
            plates: [Weight(grams: 25_000), Weight(grams: 25_000)], platePairCounts: [2, 1])

        #expect(
            throws: RecordProjectionError.repeatedPlateDenomination(
                recordID: codingID, plate: Weight(grams: 25_000))
        ) {
            try profile.inventory()
        }
        #expect(profile.name == "the meet")
        #expect(profile.barWeight == Weight(grams: 20_000))
        #expect(profile.collarWeight == Weight(grams: 2500))
        #expect(profile.plates.map(\.grams) == [25_000, 25_000])
    }
}

@Suite("The two fallback policies agree")
struct RecordVocabularyAgreementTests {
    // `Movement`, `Equipment` and `BarType` decide their own answer to an unrecognised spelling, in
    // `PowerliftingCore`, for the seed catalogue. `RecordVocabulary` decides it again for storage.
    // The two coincide today and are allowed to diverge — but not silently, which is what this
    // pins.
    //
    // It exists because a mutation probe found it: replacing `decodeVocabulary` with a plain
    // `decode` for `Movement` **survived every test**, and the reason is that the mutant is
    // equivalent rather than that the tests are thin. An equivalent mutant is the one verdict a
    // probe reports as "survived" when nothing is wrong; the answer is to find out why, not to
    // widen the assertion.
    private func decoded<T: Decodable>(_ type: T.Type, spelling: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data("\"\(spelling)\"".utf8))
    }

    @Test("The domain types' own lenient decoders land where this module's table does")
    func decodersAgreeWithTheTable() throws {
        #expect(try decoded(Movement.self, spelling: "kettlebellSwing") == RecordVocabulary.movement.value)
        #expect(try decoded(Equipment.self, spelling: "sled") == RecordVocabulary.equipment.value)
        #expect(try decoded(BarType.self, spelling: "axle") == RecordVocabulary.barType.value)
    }

    // And the seven that do not degrade on their own, which is where the table is load-bearing:
    // three throw and four are not `Codable` at all, so a record decoding one of them through its
    // own conformance would either lose the row or not compile.
    @Test("The vocabularies with no lenient decoder still resolve")
    func strictVocabulariesStillResolve() {
        #expect(RecordVocabulary.resolve("contralateral", or: RecordVocabulary.laterality) == .bilateral)
        #expect(RecordVocabulary.resolve("mayhew", or: RecordVocabulary.e1RMFormula) == .epley)
        #expect(RecordVocabulary.resolve("bankers", or: RecordVocabulary.roundingStrategy) == .nearest)
        #expect(RecordVocabulary.resolve("stones", or: RecordVocabulary.displayUnit) == .kilograms)
        #expect(RecordVocabulary.resolve("smartScale", or: RecordVocabulary.bodyweightSource) == .manual)
        #expect(RecordVocabulary.resolve("sepia", or: RecordVocabulary.theme) == .system)
        #expect(
            RecordVocabulary.resolve("percentOfVelocityLoss", or: RecordVocabulary.trainingMaxSource)
                == .manual)
    }

    // A recognised spelling is not degraded, which the fallback assertions above cannot show: every
    // one of them would also pass for a `resolve` that ignored its input entirely.
    @Test("A recognised spelling resolves to itself")
    func recognisedSpellingsSurvive() {
        #expect(RecordVocabulary.resolve("unilateral", or: RecordVocabulary.laterality) == .unilateral)
        #expect(RecordVocabulary.resolve("wathan", or: RecordVocabulary.e1RMFormula) == .wathan)
        #expect(RecordVocabulary.resolve("dark", or: RecordVocabulary.theme) == .dark)
    }
}

@Suite("A refusal is equal to itself")
struct RecordProjectionErrorEqualityTests {
    private static let id = UUID(uuidString: "0f7b6a5c-1111-4222-8333-444455556666") ?? UUID()
    private static let other = UUID(uuidString: "0f7b6a5c-7777-4888-8999-aaaabbbbcccc") ?? UUID()

    /// One instance of every case, with the two `ReportedNumber` payloads carrying NaN — the values
    /// the wrapper exists for, and the ones a bare `Double` payload would make non-reflexive.
    private static let everyCase: [RecordProjectionError] = [
        .plateListsDisagreeInLength(recordID: id, plates: 2, pairCounts: 1),
        .plateUnderOneGram(recordID: id, plate: Weight(grams: 0)),
        .negativePlatePairCount(recordID: id, plate: Weight(grams: 15_000), pairs: -1),
        .repeatedPlateDenomination(recordID: id, plate: Weight(grams: 25_000)),
        .plateInventoryOverflows(recordID: id),
        .trainingMaxPayloadMissing(recordID: id, source: .manual),
        .trainingMaxPercentageUnusable(recordID: id, percentage: .nan),
        .roundingIncrementUnloadable(recordID: id, increment: Weight(grams: 0)),
        .repsOutOfRange(recordID: id, reps: -1),
        .rpeOutOfRange(recordID: id, rpe: .nan),
        .rirOutOfRange(recordID: id, rir: 10),
        .setRefusedByDomainType(recordID: id),
        .trainingMaxRefusedByDomainType(recordID: id),
    ]

    // The property a synthesised conformance gave for eleven of the thirteen cases and silently
    // withheld for the two carrying a `Double` — NaN is not equal to itself under `Double.==`, and
    // NaN is exactly what those two cases are raised for. A caller collecting refusals into a `Set`
    // to deduplicate repair messages got one entry per occurrence, and `contains` was false for an
    // error it had just inserted.
    @Test("Every refusal equals itself", arguments: everyCase)
    func everyRefusalEqualsItself(_ refusal: RecordProjectionError) {
        #expect(refusal == refusal)
    }

    // The half reflexivity does not give, and the half a first draft got wrong: an `==` that
    // ignored `recordID` on one case passed it, because `everyCase` varies the *case* and nothing
    // else. This list varies **one payload at a time, on every payload of every case**, so an arm
    // of the hand-written switch that drops a binding collides with its neighbour and the count
    // falls. It is the same defect T-0.40's review found in `RepositoryError`'s suite — two
    // refusals that agreed on `recordID` and differed only in the second payload — recurring one
    // type later, and found the same way.
    //
    // **Compared pairwise with `==` rather than through a `Set`, and that is a finding rather than
    // a style choice.** A `Set` consults `hash(into:)` first and only calls `==` within a bucket, so
    // an `==` that is *coarser* than the hash — exactly what dropping a `recordID` binding produces,
    // since `hash(into:)` here is synthesised and still reads it — never gets asked. The set-based
    // version of this test passed the mutation it was written for. Any distinctness claim about a
    // hand-written `==` has to call `==`.
    private static let everyPayloadVaried: [RecordProjectionError] =
        everyCase + [
            .plateListsDisagreeInLength(recordID: other, plates: 2, pairCounts: 1),
            .plateListsDisagreeInLength(recordID: id, plates: 3, pairCounts: 1),
            .plateListsDisagreeInLength(recordID: id, plates: 2, pairCounts: 2),
            .plateUnderOneGram(recordID: other, plate: Weight(grams: 0)),
            .plateUnderOneGram(recordID: id, plate: Weight(grams: -1)),
            .negativePlatePairCount(recordID: other, plate: Weight(grams: 15_000), pairs: -1),
            .negativePlatePairCount(recordID: id, plate: Weight(grams: 20_000), pairs: -1),
            .negativePlatePairCount(recordID: id, plate: Weight(grams: 15_000), pairs: -2),
            .repeatedPlateDenomination(recordID: other, plate: Weight(grams: 25_000)),
            .repeatedPlateDenomination(recordID: id, plate: Weight(grams: 20_000)),
            .plateInventoryOverflows(recordID: other),
            .trainingMaxPayloadMissing(recordID: other, source: .manual),
            .trainingMaxPayloadMissing(recordID: id, source: .percentOfRepMax),
            .trainingMaxPercentageUnusable(recordID: other, percentage: .nan),
            .trainingMaxPercentageUnusable(recordID: id, percentage: 0),
            .roundingIncrementUnloadable(recordID: other, increment: Weight(grams: 0)),
            .roundingIncrementUnloadable(recordID: id, increment: Weight(grams: -1)),
            .repsOutOfRange(recordID: other, reps: -1),
            .repsOutOfRange(recordID: id, reps: -2),
            .rpeOutOfRange(recordID: other, rpe: .nan),
            .rpeOutOfRange(recordID: id, rpe: 11),
            .rirOutOfRange(recordID: other, rir: 10),
            .rirOutOfRange(recordID: id, rir: 11),
            .setRefusedByDomainType(recordID: other),
            .trainingMaxRefusedByDomainType(recordID: other),
        ]

    @Test("Refusals differing in any single payload stay distinct")
    func distinctRefusalsAreDistinct() {
        let refusals = Self.everyPayloadVaried
        var collisions: [String] = []
        for (index, one) in refusals.enumerated() {
            for other in refusals[refusals.index(after: index)...] where one == other {
                collisions.append("\(one) == \(other)")
            }
        }

        #expect(collisions.isEmpty, "distinct refusals compare equal: \(collisions.joined(separator: "; "))")
    }

    // And the consequence the whole conformance is for: a repair caller can deduplicate.
    @Test("A refusal can be found in a set it was put into")
    func refusalsSurviveASet() {
        let refusal = RecordProjectionError.rpeOutOfRange(recordID: Self.id, rpe: .nan)
        var collected: Set<RecordProjectionError> = []
        collected.insert(refusal)
        collected.insert(refusal)

        #expect(collected.contains(refusal))
        #expect(collected.count == 1)
    }
}
