import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

@Suite("TrainingMaxConfigEntity")
struct TrainingMaxConfigEntityTests {
    @Test("Every field survives a save and a re-read")
    func roundTrips() throws {
        let context = try makeSupportingContext()
        let exerciseID = UUID()
        let effective = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(
            makeTrainingMaxConfig(
                exerciseID: exerciseID,
                source: .percentOfRepMax,
                percentage: 0.925,
                roundingIncrementGrams: 1_250,
                roundingStrategy: .up,
                effectiveFrom: effective,
                sourceRepCount: 3,
                incrementGrams: 2_500
            )
        )
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<TrainingMaxConfigEntity>.notDeleted()).first
        )

        #expect(stored.exerciseID == exerciseID)
        #expect(stored.sourceRawValue == "percentOfRepMax")
        #expect(stored.percentage == 0.925)
        #expect(stored.roundingIncrementGrams == 1_250)
        #expect(stored.roundingStrategyRawValue == "up")
        #expect(stored.effectiveFrom == effective)
        #expect(stored.sourceRepCount == 3)
        #expect(stored.incrementGrams == 2_500)
    }

    // Gap §17. Without this column one of FR-1.5.1.1's three sources is unstorable: "90% of my best
    // 3-rep max" has nowhere for the 3. Manual's own payload is not here at all — it is a
    // `TrainingMaxHistoryEntity` row, which is where `G-1.4` puts the number.
    @Test("A rep-max source stores its N")
    func repMaxSourceStoresItsN() throws {
        let context = try makeSupportingContext()
        context.insert(makeTrainingMaxConfig(source: .percentOfRepMax, sourceRepCount: 3))
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<TrainingMaxConfigEntity>.notDeleted()).first
        )

        #expect(stored.sourceRepCount == 3)
        #expect(stored.sourceRawValue == "percentOfRepMax")
    }

    // Gap §18, the half a schema can hold. A manual training max is the number entered, untouched by
    // the percentage and the rounding rule — and the two rows here prove that no column but `source`
    // records that. They are identical in every other column, which is the point: after the number
    // moved to `TrainingMaxHistoryEntity` the discriminator is the *only* difference there is.
    @Test("Only the source column says whether the percentage and rounding took part")
    func onlyTheSourceColumnMarksParticipation() throws {
        let context = try makeSupportingContext()
        let derived = makeTrainingMaxConfig(
            source: .percentOfE1RM,
            percentage: 0.9,
            roundingIncrementGrams: 2_500,
            roundingStrategy: .nearest
        )
        let manual = makeTrainingMaxConfig(
            source: .manual,
            percentage: 0.9,
            roundingIncrementGrams: 2_500,
            roundingStrategy: .nearest
        )
        context.insert(derived)
        context.insert(manual)
        try context.saveStamped()

        let stored = try context.fetch(
            FetchDescriptor<TrainingMaxConfigEntity>.notDeleted(
                sortBy: [SortDescriptor(\.sourceRawValue)]
            )
        )

        // Anchored to literals on both sides: comparing the two rows with each other would agree
        // just as happily if either column read back empty.
        #expect(stored.map(\.sourceRawValue) == ["manual", "percentOfE1RM"])
        #expect(stored.map(\.percentage) == [0.9, 0.9])
        #expect(stored.map(\.roundingIncrementGrams) == [2_500, 2_500])
        #expect(stored.map(\.roundingStrategyRawValue) == ["nearest", "nearest"])
    }

    // …and why the columns cannot carry that signal themselves. The two values a row could wear to
    // mean "did not participate" are exactly the ones the domain types refuse, so a row marked that
    // way could not be mapped back to a configuration at all. This is the evidence for the decision
    // above, not decoration: without it, "no in-band marker is available" is an assertion nothing
    // checks.
    @Test("Neither a zero percentage nor a zero increment is an available marker")
    func noInBandMarkerExists() throws {
        let rule = try #require(RoundingRule(increment: Weight(grams: 2_500), strategy: .nearest))
        let entered = Weight(grams: 102_400)

        #expect(RoundingRule(increment: Weight(grams: 0), strategy: .nearest) == nil)
        #expect(
            TrainingMaxConfiguration(source: .manual(entered), percentage: 0, rounding: rule) == nil
        )
        // The positive control, without which both refusals above could be an initialiser that
        // never constructs anything.
        #expect(
            TrainingMaxConfiguration(source: .manual(entered), percentage: 0.9, rounding: rule)
                != nil
        )
    }

    // A manual row's percentage and rule are the configuration FR-1.5.1.5's one-tap "recalculate
    // from e1RM" returns to, so they have to come back exactly as written rather than be reset to
    // the schema defaults on the way through. Both fixture values differ from those defaults.
    @Test("A manual row preserves the dormant configuration it will be switched back to")
    func manualRowPreservesItsDormantConfiguration() throws {
        let context = try makeSupportingContext()
        context.insert(
            makeTrainingMaxConfig(
                source: .manual,
                percentage: 0.85,
                roundingIncrementGrams: 5_000,
                roundingStrategy: .down
            )
        )
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<TrainingMaxConfigEntity>.notDeleted()).first
        )

        #expect(stored.percentage == 0.85)
        #expect(stored.percentage != SchemaDefaults.trainingMaxPercentage)
        #expect(stored.roundingIncrementGrams == 5_000)
        #expect(stored.roundingIncrementGrams != SchemaDefaults.roundingIncrementGrams)
        #expect(stored.roundingStrategyRawValue == "down")
    }

    // The query effectiveFrom exists for, and the one SchemaDefaults.effectiveFrom's *direction* is
    // argued from — so the argument needs this rather than a doc comment. FR-1.5.1.4 keeps every
    // change, so a read is "the latest row for this exercise effective on or before D", and it has to
    // be expressible from the columns alone: there is no relationship to traverse (G-2.5). The
    // defaulted row is in the fixture on purpose — a foreign row must *lose* to every real
    // configuration, which is the whole reason the default is the distant past and not now.
    @Test("The latest configuration effective on or before a date is readable from the columns alone")
    func theLatestEffectiveConfigurationWins() throws {
        let context = try makeSupportingContext()
        let squat = UUID()
        let bench = UUID()
        let january = Date(timeIntervalSince1970: 1_700_000_000)
        let march = Date(timeIntervalSince1970: 1_705_000_000)
        let june = Date(timeIntervalSince1970: 1_710_000_000)
        let asOf = Date(timeIntervalSince1970: 1_707_000_000)
        for (percentage, effective) in [(0.80, january), (0.85, march), (0.90, june)] {
            context.insert(
                makeTrainingMaxConfig(
                    exerciseID: squat,
                    source: .percentOfE1RM,
                    percentage: percentage,
                    effectiveFrom: effective
                )
            )
        }
        context.insert(
            makeTrainingMaxConfig(
                exerciseID: squat,
                source: .manual,
                percentage: 0.5,
                effectiveFrom: SchemaDefaults.effectiveFrom
            )
        )
        // A second exercise at the winning date, so the predicate has to filter on both axes rather
        // than pick the only row there is.
        context.insert(
            makeTrainingMaxConfig(
                exerciseID: bench,
                source: .percentOfE1RM,
                percentage: 0.95,
                effectiveFrom: march
            )
        )
        try context.saveStamped()

        let rows = try context.fetch(
            FetchDescriptor<TrainingMaxConfigEntity>.notDeleted(
                matching: #Predicate { $0.exerciseID == squat && $0.effectiveFrom <= asOf },
                sortBy: [SortDescriptor(\.effectiveFrom, order: .reverse)]
            )
        )

        // June is excluded as not yet effective, bench is excluded as another exercise, and the
        // defaulted row sorts last rather than winning.
        #expect(rows.map(\.percentage) == [0.85, 0.80, 0.5])
        #expect(rows.first?.effectiveFrom == march)
        #expect(rows.last?.effectiveFrom == SchemaDefaults.effectiveFrom)
    }

    // incrementGrams is FR-1.5.1.3's block-completion step, not the rounding increment, and the two
    // are independent quantities that a single row must be able to disagree about.
    @Test("The progression increment is a separate quantity from the rounding increment")
    func progressionIncrementIsNotTheRoundingIncrement() throws {
        let context = try makeSupportingContext()
        context.insert(
            makeTrainingMaxConfig(
                source: .percentOfE1RM,
                roundingIncrementGrams: 2_500,
                incrementGrams: 5_000
            )
        )
        context.insert(makeTrainingMaxConfig(source: .percentOfE1RM, incrementGrams: nil))
        try context.saveStamped()

        let stored = try context.fetch(
            FetchDescriptor<TrainingMaxConfigEntity>.notDeleted(
                sortBy: [SortDescriptor(\.roundingIncrementGrams)]
            )
        )

        #expect(stored.map(\.roundingIncrementGrams) == [2_500, 5_000])
        // nil is "no automatic progression", which a non-optional column could not tell from a
        // configured step of zero — the reading TR-0.3.6's plain spelling cannot express.
        #expect(stored.map(\.incrementGrams) == [5_000, nil])
    }
}
