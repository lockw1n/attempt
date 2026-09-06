import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

// Split out of `ProjectionTests.swift` for size, along its suite boundary: that file crossed
// the 500-line ceiling once `FR-16.7` moved the manual weight out of the record and into the
// projection's parameter list. The three other projections stay together there.

@Suite("TrainingMaxEntry → TrainingMaxConfiguration")
struct TrainingMaxProjectionTests {
    private func entry(
        source: TrainingMaxSourceKind,
        sourceRepCount: Int? = 3,
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
            percentage: percentage,
            roundingIncrement: roundingIncrement,
            roundingStrategy: .down,
            progressionIncrement: Weight(grams: 2500),
            effectiveFrom: codingCreatedAt
        )
    }

    /// The projection with the manual weight the history would have supplied.
    ///
    /// **The weight is a parameter of the projection now, not a column of the row** — a manual
    /// training max lives in `TrainingMaxHistoryEntry`, so the pairing this suite is about is
    /// between the row's source and a value handed in beside it.
    private func configuration(
        source: TrainingMaxSourceKind,
        sourceRepCount: Int? = 3,
        manualWeight: Weight? = Weight(grams: 180_000),
        percentage: Double = 0.85,
        roundingIncrement: Weight = Weight(grams: 5000)
    ) throws(RecordProjectionError) -> TrainingMaxConfiguration {
        try entry(
            source: source,
            sourceRepCount: sourceRepCount,
            percentage: percentage,
            roundingIncrement: roundingIncrement
        ).configuration(manualWeight: manualWeight)
    }

    @Test("Each of the three sources projects with its own payload")
    func eachSourceProjects() throws {
        #expect(try configuration(source: .percentOfE1RM).source == .percentOfE1RM)
        #expect(try configuration(source: .percentOfRepMax).source == .percentOfRepMax(reps: 3))
        #expect(try configuration(source: .manual).source == .manual(Weight(grams: 180_000)))
    }

    // The percentage and the rounding rule are carried whatever the source, because a manual
    // training max keeps both as the dormant configuration its one-tap recalculation resumes with.
    // A projection that reset them for a manual row would make FR-1.5.1.5 a one-way door.
    @Test("A manual entry keeps its percentage and rounding rule")
    func manualKeepsItsDormantConfiguration() throws {
        let manual = try configuration(source: .manual)

        #expect(manual.percentage == 0.85)
        #expect(manual.rounding.increment == Weight(grams: 5000))
        #expect(manual.rounding.strategy == .down)
        #expect(manual.progressionIncrement == Weight(grams: 2500))
    }

    // What the schema's `.manual` default is chosen to produce: a visible refusal rather than 90%
    // of the user's e1RM handed back as though they had asked for it. Manual's payload is now the
    // caller's to supply — a lifter with a configuration and no history entry is exactly the row
    // this refuses.
    @Test("A source whose payload is missing is refused, and the source is named")
    func missingPayloadRefuses() {
        #expect(
            throws: RecordProjectionError.trainingMaxPayloadMissing(
                recordID: codingID, source: .manual)
        ) {
            try configuration(source: .manual, manualWeight: nil)
        }
        #expect(
            throws: RecordProjectionError.trainingMaxPayloadMissing(
                recordID: codingID, source: .percentOfRepMax)
        ) {
            try configuration(source: .percentOfRepMax, sourceRepCount: nil)
        }
    }

    // `.percentOfE1RM` reads neither payload, so a row with the rep count nil and no weight handed
    // in still projects — which is what makes the refusal above about the *pairing* rather than
    // about nullability.
    @Test("A percent-of-e1RM entry projects with neither payload supplied")
    func percentOfE1RMNeedsNoPayload() throws {
        let derived = try configuration(
            source: .percentOfE1RM, sourceRepCount: nil, manualWeight: nil)

        #expect(derived.source == .percentOfE1RM)
    }

    @Test("A non-positive percentage is refused, and named", arguments: [0.0, -0.5])
    func unusablePercentageRefuses(_ percentage: Double) {
        #expect(
            throws: RecordProjectionError.trainingMaxPercentageUnusable(
                recordID: codingID, percentage: ReportedNumber(percentage))
        ) {
            try configuration(source: .percentOfE1RM, percentage: percentage)
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
            try configuration(source: .percentOfE1RM, percentage: .nan)
        }
    }

    @Test("An increment below one gram is refused, and named")
    func unloadableIncrementRefuses() {
        #expect(
            throws: RecordProjectionError.roundingIncrementUnloadable(
                recordID: codingID, increment: Weight(grams: 0))
        ) {
            try configuration(source: .percentOfE1RM, roundingIncrement: Weight(grams: 0))
        }
    }

    // One gram is the identity rule — how a caller asks for no rounding — and the boundary the
    // refusal sits on.
    @Test("A one-gram increment is not a refusal")
    func oneGramIncrementIsLegal() throws {
        let derived = try configuration(
            source: .percentOfE1RM, roundingIncrement: Weight(grams: 1))

        #expect(derived.rounding.increment == Weight(grams: 1))
    }
}
