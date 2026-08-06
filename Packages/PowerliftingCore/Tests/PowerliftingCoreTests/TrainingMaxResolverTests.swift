import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## What is being asserted here
//
// Contract behaviour. Every gram figure is either a logged load chosen by the fixture, Epley's or
// Brzycki's from `E1RMFormulaTests`' reference table, or an arithmetic result written out in the
// test that produces it. Refusals compare the whole `TrainingMaxResolution`, so an assertion names
// *which* reason rather than only that resolution failed — the two derived sources refuse for
// different reasons over the same log, and a test that could not tell them apart would pass for
// the wrong one.
//
// `sourceLog` carries three properties at once: the warmup is the heaviest set in it, so a leak
// changes an answer; the best estimate is *not* the last set, so reading the wrong one is visible;
// and no set exceeds five reps, so a six-rep source is a real absence rather than a range refusal.

/// One exercise's sets, oldest first.
///
/// | # | set | |
/// |---|---|---|
/// | 0 | 150 kg × 5, warmup | heavier than everything: a leak takes every record |
/// | 1 | 100 kg × 5 | holds the 3RM–5RM |
/// | 2 | 110 kg × 2 | holds the 1RM–2RM, and the best e1RM at 117 333 |
/// | 3 | 100 kg × 5 | the *last* set, and estimates lower than offset 2 at 116 667 |
private func sourceLog() throws -> [SetRecord] {
    [
        try #require(
            SetRecord(weight: Weight(grams: 150_000), reps: 5, isWarmup: true, isCompleted: true)),
        try workingSet(Weight(grams: 100_000), reps: 5),
        try workingSet(Weight(grams: 110_000), reps: 2),
        try workingSet(Weight(grams: 100_000), reps: 5),
    ]
}

/// Builds a configuration, failing the test rather than force unwrapping.
private func configuration(
    _ source: TrainingMaxSource,
    percentage: Double = TrainingMaxConfiguration.defaultPercentage,
    increment: Weight = Increments.twoAndAHalfKilograms,
    strategy: RoundingStrategy = .nearest,
    progressionIncrement: Weight? = nil
) throws -> TrainingMaxConfiguration {
    try #require(
        TrainingMaxConfiguration(
            source: source,
            percentage: percentage,
            rounding: try roundingRule(increment, strategy),
            progressionIncrement: progressionIncrement))
}

@Suite("Training max — the three source paths")
struct TrainingMaxSourceTests {
    private let resolver = TrainingMaxResolver(.epley)

    @Test("% of e1RM reads the best estimate in the log, not the most recent one")
    func percentOfE1RMReadsTheBestEstimate() throws {
        let log = try sourceLog()
        // Offset 2 estimates at 117 333 and the last set at 116 667, so the two readings differ by
        // 600 g before the percentage — enough to survive a one-gram rounding rule.
        #expect(Epley().estimate(for: log[3]) == Weight(grams: 116_667))
        let resolution = resolver.resolve(
            try configuration(.percentOfE1RM, increment: Increments.oneGram), from: log)
        #expect(
            resolution
                == .resolved(
                    TrainingMax(weight: Weight(grams: 105_600), sourceWeight: Weight(grams: 117_333))))
    }

    @Test("% of best N-rep max reads the rep max for that N, warmups excluded")
    func percentOfRepMaxReadsTheRecordForThatN() throws {
        let log = try sourceLog()
        // 110 000 × 0.9 = 99 000, which is not a multiple of 2.5 kg and rounds up to 100 000.
        #expect(
            resolver.resolve(try configuration(.percentOfRepMax(reps: 1)), from: log)
                == .resolved(
                    TrainingMax(weight: Weight(grams: 100_000), sourceWeight: Weight(grams: 110_000))))
        // 100 000 × 0.9 = 90 000, already on the grid. Were the 150 kg warmup a candidate this
        // would be 135 000 instead.
        #expect(
            resolver.resolve(try configuration(.percentOfRepMax(reps: 5)), from: log)
                == .resolved(
                    TrainingMax(weight: Weight(grams: 90_000), sourceWeight: Weight(grams: 100_000))))
    }

    @Test("A manual training max is the number entered — neither the percentage nor the rule apply")
    func manualBypassesThePercentageAndTheRule() throws {
        let entered = Weight(grams: 102_483)
        let manual = try configuration(.manual(entered), percentage: 0.5)
        #expect(
            resolver.resolve(manual, from: try sourceLog())
                == .resolved(TrainingMax(weight: entered, sourceWeight: entered)))
        // The same percentage and rule over a *derived* source of the same weight land elsewhere —
        // 51 241.5 g rounds to 51 242 and then down to 50 000 — so the equality above is the bypass
        // rather than a coincidence of the numbers.
        let derived = try configuration(.percentOfRepMax(reps: 1), percentage: 0.5)
        #expect(
            resolver.resolve(derived, from: [try workingSet(entered, reps: 1)])
                == .resolved(TrainingMax(weight: Weight(grams: 50_000), sourceWeight: entered)))
    }

    @Test("A manual source never reads the set collection")
    func manualIgnoresTheSets() throws {
        let manual = try configuration(.manual(Weight(grams: 140_000)))
        #expect(resolver.resolve(manual, from: []) == resolver.resolve(manual, from: try sourceLog()))
        #expect(
            resolver.resolve(manual, from: [])
                == .resolved(
                    TrainingMax(weight: Weight(grams: 140_000), sourceWeight: Weight(grams: 140_000))))
    }
}

@Suite("Training max — order of operations")
struct TrainingMaxOrderingTests {
    private let resolver = TrainingMaxResolver(.epley)

    @Test("The rounding rule is applied after the percentage, and the reverse gives another answer")
    func roundingFollowsThePercentage() throws {
        let source = Weight(grams: 103_000)
        let log = [try workingSet(source, reps: 1)]
        let config = try configuration(.percentOfRepMax(reps: 1), increment: Weight(grams: 5_000))
        // 103 000 × 0.9 = 92 700, which rounds up to 95 000 on a 5 kg step.
        #expect(
            resolver.resolve(config, from: log)
                == .resolved(TrainingMax(weight: Weight(grams: 95_000), sourceWeight: source)))
        // Rounding first gives 105 000 × 0.9 = 94 500 — a 500 g difference that nothing downstream
        // would flag, which is why the order is pinned rather than left to read like a detail.
        let reversed = try #require(config.rounding.rounded(source).scaled(by: config.percentage))
        #expect(reversed == Weight(grams: 94_500))
    }

    @Test("The percentage lands on whole grams by rounding, not by truncation")
    func theScaledWeightIsRoundedToTheNearestGram() throws {
        // 103 001 × 0.9 = 92 700.9. The gram step is a representation decision and is `.nearest`;
        // the rule here is the identity, so nothing else can be doing the rounding.
        let source = Weight(grams: 103_001)
        let config = try configuration(.percentOfRepMax(reps: 1), increment: Increments.oneGram)
        #expect(
            resolver.resolve(config, from: [try workingSet(source, reps: 1)])
                == .resolved(TrainingMax(weight: Weight(grams: 92_701), sourceWeight: source)))
    }

    @Test(
        "The configured strategy is the one applied, not `.nearest` for everybody",
        arguments: [(RoundingStrategy.down, 90_000), (.up, 95_000), (.nearest, 95_000)])
    func theConfiguredStrategyIsRead(strategy: RoundingStrategy, expected: Int) throws {
        // 103 000 × 0.9 = 92 700 sits between two 5 kg multiples, so floor and ceiling differ and
        // one of them is not `.nearest`'s answer. Without this the resolver could ignore
        // `RoundingStrategy` entirely — measured: hardcoding `.nearest` failed no test at all.
        let source = Weight(grams: 103_000)
        let config = try configuration(
            .percentOfRepMax(reps: 1), increment: Weight(grams: 5_000), strategy: strategy)
        #expect(
            resolver.resolve(config, from: [try workingSet(source, reps: 1)])
                == .resolved(TrainingMax(weight: Weight(grams: expected), sourceWeight: source)))
    }

    @Test("A rule can floor a real source to a training max of zero, which is still a value")
    func roundingDownCanReachZero() throws {
        // 1 kg × 0.9 = 900 g, and the floor of that on a 2.5 kg step is 0. The zero here is the
        // rule's answer rather than an absence, and `FR-2.3.5` has to keep telling them apart.
        let source = Weight(grams: 1_000)
        let config = try configuration(.percentOfRepMax(reps: 1), strategy: .down)
        let resolution = resolver.resolve(config, from: [try workingSet(source, reps: 1)])
        #expect(resolution == .resolved(TrainingMax(weight: .zero, sourceWeight: source)))
        #expect(resolution != .unresolvable(.noSourceData))
        // The same source under `.up` clears the step, so the zero is the direction and not the
        // source being too light to resolve at all.
        let up = try configuration(.percentOfRepMax(reps: 1), strategy: .up)
        #expect(
            resolver.resolve(up, from: [try workingSet(source, reps: 1)])
                == .resolved(TrainingMax(weight: Weight(grams: 2_500), sourceWeight: source)))
    }

    @Test("The progression increment is carried and never applied")
    func theProgressionIncrementDoesNotMoveTheAnswer() throws {
        let log = try sourceLog()
        let plain = try configuration(.percentOfRepMax(reps: 1))
        let progressing = try configuration(
            .percentOfRepMax(reps: 1), progressionIncrement: Increments.twoAndAHalfKilograms)
        // `FR-1.5.1.3` applies this on block completion, which rewrites the configuration. Applying
        // it at resolution would add one increment on every read.
        #expect(progressing.progressionIncrement == Increments.twoAndAHalfKilograms)
        #expect(resolver.resolve(progressing, from: log) == resolver.resolve(plain, from: log))
        #expect(
            resolver.resolve(progressing, from: log)
                == .resolved(
                    TrainingMax(weight: Weight(grams: 100_000), sourceWeight: Weight(grams: 110_000))))
    }
}

@Suite("Training max — the sign of the source weight")
struct TrainingMaxSignTests {
    private let resolver = TrainingMaxResolver(.epley)

    @Test("The boundary is below zero, and zero resolves")
    func negativeIsRefusedAndZeroIsNot() throws {
        let config = try configuration(.percentOfRepMax(reps: 1), increment: Increments.oneGram)
        func resolve(_ grams: Int) throws -> TrainingMaxResolution {
            resolver.resolve(config, from: [try workingSet(Weight(grams: grams), reps: 1)])
        }
        #expect(try resolve(-1) == .unresolvable(.negativeSourceWeight(Weight(grams: -1))))
        // A training max of zero is a value, not an absence — `FR-2.3.5` has to tell them apart,
        // and a zero returned as a sentinel is what this whole enum exists to avoid.
        #expect(try resolve(0) == .resolved(TrainingMax(weight: .zero, sourceWeight: .zero)))
        #expect(try resolve(0) != .unresolvable(.noSourceData))
        #expect(
            try resolve(1)
                == .resolved(TrainingMax(weight: Weight(grams: 1), sourceWeight: Weight(grams: 1))))
    }

    @Test("A manual entry meets the same boundary")
    func aManualNegativeIsRefusedToo() throws {
        let negative = try configuration(.manual(Weight(grams: -1)))
        #expect(
            resolver.resolve(negative, from: [])
                == .unresolvable(.negativeSourceWeight(Weight(grams: -1))))
        #expect(
            resolver.resolve(try configuration(.manual(.zero)), from: [])
                == .resolved(TrainingMax(weight: .zero, sourceWeight: .zero)))
    }

    @Test("Assisted work has a rep max and no training max, and each source refuses differently")
    func assistedWorkIsRefusedAtTheTrainingMaxRatherThanAtTheRecord() throws {
        let log = [
            try workingSet(Weight(grams: -20_000), reps: 5),
            try workingSet(Weight(grams: -10_000), reps: 5),
        ]
        // The record itself is real and correctly ranked — less assistance is the heavier lift.
        #expect(
            resolver.records.repMax(forReps: 5, in: log)
                == PersonalRecord(weight: Weight(grams: -10_000), setOffset: 1))
        #expect(
            resolver.resolve(try configuration(.percentOfRepMax(reps: 5)), from: log)
                == .unresolvable(.negativeSourceWeight(Weight(grams: -10_000))))
        // The e1RM path never sees a negative: `E1RMCalculator` refused every set first, so this is
        // an absence of source data rather than a sign refusal (requirements gap 13).
        #expect(
            resolver.resolve(try configuration(.percentOfE1RM), from: log)
                == .unresolvable(.noSourceData))
    }
}

@Suite("Training max — the refusals")
struct TrainingMaxRefusalTests {
    private let resolver = TrainingMaxResolver(.epley)

    @Test("A rep count outside 1...10 is refused by name", arguments: [-1, 0, 11, 12])
    func repCountsOutsideTheRangeAreNamed(reps: Int) throws {
        let log = try sourceLog()
        #expect(
            resolver.resolve(try configuration(.percentOfRepMax(reps: reps)), from: log)
                == .unresolvable(.repCountOutOfRange(reps)))
        #expect(PersonalRecords.repRange.contains(reps) == false)
        // The same log resolves for an N inside the range, so the refusal is the N and not the log.
        #expect(
            resolver.resolve(try configuration(.percentOfRepMax(reps: 1)), from: log)
                == .resolved(
                    TrainingMax(weight: Weight(grams: 100_000), sourceWeight: Weight(grams: 110_000))))
    }

    @Test("An N nobody reached is a different answer from an N nobody computes")
    func anUnreachedRepCountIsNotAnOutOfRangeOne() throws {
        let log = try sourceLog()
        // Six is inside `repRange`, and no set in the log reached it.
        #expect(PersonalRecords.repRange.contains(6))
        #expect(
            resolver.resolve(try configuration(.percentOfRepMax(reps: 6)), from: log)
                == .unresolvable(.noSourceData))
        #expect(
            resolver.resolve(try configuration(.percentOfRepMax(reps: 11)), from: log)
                == .unresolvable(.repCountOutOfRange(11)))
    }

    @Test("An empty log refuses both derived sources and neither manual one")
    func anEmptyLogHasNoSourceData() throws {
        #expect(
            resolver.resolve(try configuration(.percentOfE1RM), from: []) == .unresolvable(.noSourceData))
        #expect(
            resolver.resolve(try configuration(.percentOfRepMax(reps: 1)), from: [])
                == .unresolvable(.noSourceData))
        #expect(
            resolver.resolve(try configuration(.manual(Weight(grams: 100_000))), from: [])
                == .resolved(
                    TrainingMax(weight: Weight(grams: 100_000), sourceWeight: Weight(grams: 100_000))))
    }

    @Test("A source that will not scale into Int grams is refused rather than trapping")
    func anUnrepresentableProductIsRefused() throws {
        let config = try configuration(.percentOfRepMax(reps: 1), percentage: 2)
        #expect(
            resolver.resolve(config, from: [try workingSet(Weight(grams: .max), reps: 1)])
                == .unresolvable(.notRepresentable))
        // The same configuration over a plausible load resolves, and above its source — a
        // percentage over 1 is deliberately allowed.
        #expect(
            resolver.resolve(config, from: [try workingSet(Weight(grams: 100_000), reps: 1)])
                == .resolved(
                    TrainingMax(weight: Weight(grams: 200_000), sourceWeight: Weight(grams: 100_000))))
    }
}

@Suite("Training max — the configuration")
struct TrainingMaxConfigurationTests {
    @Test(
        "A percentage that is not finite and positive is rejected at construction",
        arguments: [0, -0.000_1, -0.9, Double.nan, .infinity, -.infinity])
    func nonPositivePercentagesAreRejected(percentage: Double) throws {
        let rule = try roundingRule(Increments.twoAndAHalfKilograms, .nearest)
        #expect(
            TrainingMaxConfiguration(
                source: .percentOfE1RM, percentage: percentage, rounding: rule) == nil)
    }

    @Test("Any finite positive percentage is accepted", arguments: [0.000_1, 0.5, 0.9, 1, 1.5])
    func finitePositivePercentagesAreAccepted(percentage: Double) throws {
        let rule = try roundingRule(Increments.twoAndAHalfKilograms, .nearest)
        let config = try #require(
            TrainingMaxConfiguration(source: .percentOfE1RM, percentage: percentage, rounding: rule))
        #expect(config.percentage == percentage)
    }

    @Test("The default percentage is 90%, and it is what omitting the argument gives")
    func theDefaultPercentageIsNinetyPercent() throws {
        #expect(TrainingMaxConfiguration.defaultPercentage == 0.9)
        let rule = try roundingRule(Increments.twoAndAHalfKilograms, .nearest)
        let config = try #require(TrainingMaxConfiguration(source: .percentOfE1RM, rounding: rule))
        #expect(config.percentage == 0.9)
        #expect(config.progressionIncrement == nil)
        #expect(config.rounding == rule)
        #expect(config.source == .percentOfE1RM)
    }

    @Test("Only the manual case is manual")
    func isManualNamesOneCase() {
        #expect(TrainingMaxSource.manual(Weight(grams: 100_000)).isManual)
        #expect(TrainingMaxSource.percentOfE1RM.isManual == false)
        #expect(TrainingMaxSource.percentOfRepMax(reps: 1).isManual == false)
    }

    @Test("A one-gram increment is the rule that does not round")
    func aOneGramIncrementIsTheIdentity() throws {
        let config = try configuration(.percentOfRepMax(reps: 1), percentage: 1, increment: Increments.oneGram)
        let odd = Weight(grams: 102_483)
        #expect(
            TrainingMaxResolver(.epley).resolve(config, from: [try workingSet(odd, reps: 1)])
                == .resolved(TrainingMax(weight: odd, sourceWeight: odd)))
    }
}

@Suite("Training max — the formula it reads through")
struct TrainingMaxFormulaTests {
    @Test("Switching the formula moves the e1RM source and leaves the rep-max source alone")
    func theFormulaReachesOnlyTheEstimateSource() throws {
        // `G-1.4`: nothing is cached, so `FR-1.7.3`'s recalculation is a settings change. Both
        // figures are Epley's and Brzycki's for the 110 kg × 2 at offset 2.
        let log = try sourceLog()
        let e1rm = try configuration(.percentOfE1RM, increment: Increments.oneGram)
        #expect(
            TrainingMaxResolver(.epley).resolve(e1rm, from: log)
                == .resolved(
                    TrainingMax(weight: Weight(grams: 105_600), sourceWeight: Weight(grams: 117_333))))
        #expect(
            TrainingMaxResolver(.brzycki).resolve(e1rm, from: log)
                == .resolved(
                    TrainingMax(weight: Weight(grams: 101_829), sourceWeight: Weight(grams: 113_143))))
        // Rep maxes read logged loads, so they do not move.
        let repMax = try configuration(.percentOfRepMax(reps: 1), increment: Increments.oneGram)
        #expect(
            TrainingMaxResolver(.brzycki).resolve(repMax, from: log)
                == TrainingMaxResolver(.epley).resolve(repMax, from: log))
    }

    @Test("A resolver built with no argument reads the default formula")
    func defaultFormulaIsUsed() throws {
        let log = try sourceLog()
        let e1rm = try configuration(.percentOfE1RM, increment: Increments.oneGram)
        #expect(TrainingMaxResolver().records.e1rm.formula.id == E1RMFormulaID.defaultFormula)
        #expect(
            TrainingMaxResolver().resolve(e1rm, from: log)
                == TrainingMaxResolver(.epley).resolve(e1rm, from: log))
    }
}
