import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2). That is also this task's
// determinism criterion in disguise: with no Foundation there is no `Locale` and no clock to reach
// for, and every figure below is `Int` grams compared with `==` on the value type.
//
// ## What is being asserted here
//
// Contract behaviour. Every expected weight is arithmetic anyone can redo: a basis chosen by the
// test, times a factor written beside it, snapped to an increment written beside that. The RPE
// figures are the standard chart's own cells (`RPEStandardTableTests` is where the chart itself is
// pinned), used in the direction opposite to `RPEBased`'s.
//
// Two orderings are pinned rather than described, because both are invisible once wrong: the factor
// is applied before the rounding rule, and the rounding rule is applied before — never after — the
// plate inventory is consulted. The second is the one this task had to decide; see
// `theRuleDecidesTheNumberAndThePlatesOnlyDescribeIt`.

// MARK: - Fixtures

/// Builds a context, failing the test rather than force unwrapping.
func prescriptionContext(
    increment: Weight = Increments.twoAndAHalfKilograms,
    strategy: RoundingStrategy = .nearest,
    trainingMax: TrainingMax? = nil,
    estimate: Weight? = nil,
    topSet: Weight? = nil,
    previous: Weight? = nil,
    reps: Int? = nil,
    plates: PlateCalculator? = nil
) throws -> PrescriptionContext {
    PrescriptionContext(
        rounding: try roundingRule(increment, strategy),
        trainingMax: trainingMax,
        estimatedOneRepMax: estimate,
        topSetWeight: topSet,
        previousWeight: previous,
        reps: reps,
        plates: plates)
}

/// A training max of `grams`, whose source weight is deliberately a *different* number so that
/// reading the wrong one changes an answer. See `resolutionNeverReadsTheSourceWeight`.
func prescribedTrainingMax(_ grams: Int, source: Int = 999_999) -> TrainingMax {
    TrainingMax(weight: Weight(grams: grams), sourceWeight: Weight(grams: source))
}

/// The resolved value, or `nil` when the resolution was anything else.
func resolvedPrescription(_ resolution: PrescriptionResolution) -> ResolvedPrescription? {
    guard case .resolved(let value) = resolution else { return nil }
    return value
}

/// A gym holding one pair of 20s, two pairs of 15s, one pair of 5s and **one** pair of 1.25s, on a
/// 20 kg bar without collars.
///
/// The single 1.25 pair is the point: 31.25 kg a side loads exactly and 32.5 kg does not, so a
/// 2.5 kg step in the target is the difference between a weight this gym can put on the bar and one
/// it cannot.
func sparsePlateGym() throws -> PlateCalculator {
    try plateCalculator(
        bar: 20_000, inventory: try plateInventory((20_000, 1), (15_000, 2), (5_000, 1), (1_250, 1)))
}

@Suite("Prescription resolution — the cases that name a weight")
struct PrescriptionResolverCaseTests {
    private let resolver = PrescriptionResolver()

    @Test("Each percentage case reads its own input and no other")
    func eachPercentageReadsItsOwnInput() throws {
        // Three distinct bases, a factor of 1 and a rule that cannot round, so the answer is the
        // basis itself: a case reading a neighbour's field is off by tens of kilograms.
        let context = try prescriptionContext(
            increment: Increments.oneGram,
            trainingMax: prescribedTrainingMax(100_000),
            estimate: Weight(grams: 200_000),
            topSet: Weight(grams: 50_000))
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 1), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 100_000))))
        #expect(
            resolver.resolve(.percentOfE1RM(percentage: 1), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 200_000))))
        #expect(
            resolver.resolve(.percentOfTopSet(percentage: 1), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 50_000))))
    }

    @Test("Resolution reads the training max, never the weight it was derived from")
    func resolutionNeverReadsTheSourceWeight() throws {
        // A training max carries the source it came from for `FR-1.5.1.7`'s drift comparison. It is
        // not the number a prescription is a percentage of, and the two differ by 20 kg here.
        let context = try prescriptionContext(
            increment: Increments.oneGram,
            trainingMax: TrainingMax(weight: Weight(grams: 90_000), sourceWeight: Weight(grams: 110_000)))
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 1), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 90_000))))
        // The same weight under a different source resolves identically, so the equality above is
        // the field that was read rather than a coincidence of the fixture.
        let elsewhere = try prescriptionContext(
            increment: Increments.oneGram,
            trainingMax: TrainingMax(weight: Weight(grams: 90_000), sourceWeight: .zero))
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 1), in: elsewhere)
                == resolver.resolve(.percentOfTrainingMax(percentage: 1), in: context))
    }

    @Test("The rule is applied after the factor, and the reverse gives another answer")
    func theRuleFollowsTheFactor() throws {
        let context = try prescriptionContext(trainingMax: prescribedTrainingMax(103_000))
        // 103 000 × 0.9 = 92 700, which is 37.08 steps of 2.5 kg and rounds down to 92 500.
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 0.9), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 92_500))))
        // Rounding first gives 102 500 × 0.9 = 92 250 — 250 g out, and nothing downstream would
        // flag it. Computed with real calls rather than asserted as a second literal.
        let reversed = try #require(context.rounding.rounded(Weight(grams: 103_000)).scaled(by: 0.9))
        #expect(reversed == Weight(grams: 92_250))
    }

    @Test("The factor lands on whole grams by rounding, whatever direction the rule takes")
    func theScaledWeightIsRoundedToTheNearestGram() throws {
        // 103 001 × 0.9 = 92 700.9. The gram step is the storage resolution and is always
        // `.nearest`; the rule here is the identity and its strategy is `.down`, so truncation
        // anywhere in the chain would show as 92 700.
        let context = try prescriptionContext(
            increment: Increments.oneGram,
            strategy: .down,
            trainingMax: prescribedTrainingMax(103_001))
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 0.9), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 92_701))))
    }

    @Test(
        "The context's strategy is the one applied, not `.nearest` for everybody",
        arguments: [(RoundingStrategy.down, 90_000), (.up, 95_000), (.nearest, 95_000)])
    func theConfiguredStrategyIsRead(strategy: RoundingStrategy, expected: Int) throws {
        // 103 000 × 0.9 = 92 700 sits between two 5 kg multiples, so floor and ceiling differ and
        // one of them is not what `.nearest` answers.
        let context = try prescriptionContext(
            increment: Weight(grams: 5_000),
            strategy: strategy,
            trainingMax: prescribedTrainingMax(103_000))
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 0.9), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: expected))))
    }

    @Test(
        "An RPE target is the chart's fraction of the estimate",
        arguments: [(5, 8.0, 162_200), (3, 8.5, 175_600), (1, 10.0, 200_000), (10, 10.0, 147_800)])
    func anRPETargetReadsTheChart(reps: Int, rpe: Double, expected: Int) throws {
        // Reps plus reps in reserve is the chart's key, so 5 @ 8 and 3 @ 8.5 are two different
        // cells (7 and 4.5) and 1 @ 10 is the top of the chart, where the fraction is 1.
        let context = try prescriptionContext(
            increment: Increments.oneGram, estimate: Weight(grams: 200_000), reps: reps)
        #expect(
            resolver.resolve(.rpeTarget(rpe: rpe), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: expected))))
    }

    @Test("An RPE target is rounded like every other derived weight")
    func anRPETargetIsRounded() throws {
        // 0.811 × 200 000 = 162 200, which is 64.88 steps of 2.5 kg and rounds up to 162 500.
        let context = try prescriptionContext(estimate: Weight(grams: 200_000), reps: 5)
        #expect(
            resolver.resolve(.rpeTarget(rpe: 8), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 162_500))))
    }

    @Test("A resolver reads the chart it was built with")
    func theConfiguredChartIsRead() throws {
        // One row, so every effort it answers at all resolves to half the estimate. Nothing else in
        // the pipeline can produce 50 000 from 200 000 at a factor the standard chart holds.
        let entry = RPETable.Entry(repsToFailure: 3, fractionOfMax: 0.25)
        let table = try #require(RPETable(entries: [entry], repRange: 1...10))
        let context = try prescriptionContext(
            increment: Increments.oneGram, estimate: Weight(grams: 200_000), reps: 1)
        #expect(
            PrescriptionResolver(rpeTable: table).resolve(.rpeTarget(rpe: 8), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 50_000))))
        #expect(PrescriptionResolver().rpeTable == .standard)
    }

    @Test("A weight the program states outright is not rounded")
    func statedWeightsBypassTheRule() throws {
        let odd = Weight(grams: 102_483)
        let context = try prescriptionContext(
            trainingMax: TrainingMax(weight: odd, sourceWeight: odd), previous: odd)
        #expect(
            resolver.resolve(.fixedWeight(odd), in: context)
                == .resolved(ResolvedPrescription(target: odd)))
        #expect(
            resolver.resolve(.previousPlusIncrement(.zero), in: context)
                == .resolved(ResolvedPrescription(target: odd)))
        // The same weight through a *derived* case under the same rule lands 17 g away, so the two
        // equalities above are the bypass rather than a number that happened to be on the grid.
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 1), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 102_500))))
    }

    @Test("The increment is signed, and it is added to the load that was logged")
    func aSignedIncrementIsAddedToThePreviousLoad() throws {
        let context = try prescriptionContext(previous: Weight(grams: 100_000))
        #expect(
            resolver.resolve(.previousPlusIncrement(Increments.twoAndAHalfKilograms), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 102_500))))
        // A negative step is a configured deload, not a mistake.
        #expect(
            resolver.resolve(.previousPlusIncrement(Weight(grams: -2_500)), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 97_500))))
    }

    @Test("Bodyweight work resolves to the external load alone, at any sign, with no loading")
    func bodyweightIsTheExternalLoad() throws {
        let context = try prescriptionContext(plates: try sparsePlateGym())
        for grams in [20_000, 0, -15_000] {
            #expect(
                resolver.resolve(.bodyweight(added: Weight(grams: grams)), in: context)
                    == .resolved(ResolvedPrescription(target: Weight(grams: grams))))
        }
        // Explicitly: no plate loading even though the context holds a profile. A loading carries a
        // bar and two collars, and a banded pull-up has neither.
        let resolved = try #require(
            resolvedPrescription(resolver.resolve(.bodyweight(added: Weight(grams: 20_000)), in: context)))
        #expect(resolved.loading == nil)
        // A weight of the same size through a case that *is* barbell work does get one.
        let onABar = try #require(
            resolvedPrescription(resolver.resolve(.fixedWeight(Weight(grams: 20_000)), in: context)))
        #expect(onABar.loading != nil)
    }

    @Test("AMRAP resolves, and it is not a refusal")
    func amrapNamesNoLoad() throws {
        // Nothing is missing, so there is no prompt to raise: the lifter picks the weight. The
        // context is fully populated precisely so the answer cannot be read as an absence.
        let context = try prescriptionContext(
            trainingMax: prescribedTrainingMax(100_000),
            estimate: Weight(grams: 200_000),
            topSet: Weight(grams: 150_000),
            previous: Weight(grams: 140_000),
            reps: 5,
            plates: try sparsePlateGym())
        let resolution = resolver.resolve(.amrap, in: context)
        #expect(resolution == .unspecifiedLoad)
        #expect(resolution != .unresolvable(.noTrainingMax))
        #expect(resolution != .resolved(ResolvedPrescription(target: .zero)))
        // An empty context gives the same answer, since none of it was ever consulted.
        #expect(
            resolver.resolve(.amrap, in: try prescriptionContext()) == .unspecifiedLoad)
    }

    @Test("An unrecognised prescription is refused by its raw type, and its payload is not read")
    func anUnrecognisedPrescriptionNamesItsKind() throws {
        // The payload holds a plausible weight and a plausible percentage. Reading either would be
        // guessing at a newer version's meaning, which is the corruption `NFR-2.3` avoids.
        let unrecognised = try #require(
            UnrecognisedPrescription(
                kind: "wavePercent",
                schemaVersion: 2,
                payload: ["weight": .int(102_500), "percentage": .double(0.85)]))
        let context = try prescriptionContext(trainingMax: prescribedTrainingMax(100_000))
        #expect(
            resolver.resolve(.unrecognised(unrecognised), in: context)
                == .unresolvable(.unrecognisedPrescription(kind: "wavePercent")))
    }
}
