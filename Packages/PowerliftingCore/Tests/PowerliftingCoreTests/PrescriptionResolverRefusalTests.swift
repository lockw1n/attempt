import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## What is being asserted here
//
// `FR-2.3.5` asks for a refusal that names what was missing, so every assertion below compares the
// whole `PrescriptionResolution` and therefore names *which* reason. A test that only established
// that resolution failed would pass for the wrong prompt — and the prompts differ: "set a training
// max" and "log your top set first" are different sentences to a lifter halfway through a session.
//
// Each missing-input refusal is paired with the same context plus the input, so the refusal is
// demonstrably the absence rather than the case being broken.

@Suite("Prescription resolution — the inputs that were missing")
struct PrescriptionResolverMissingInputTests {
    private let resolver = PrescriptionResolver()

    @Test("An empty context refuses each case by the input it needed")
    func eachCaseNamesTheInputItIsMissing() throws {
        let empty = try prescriptionContext()
        let expected: [(Prescription, PrescriptionUnresolvedReason)] = [
            (.percentOfTrainingMax(percentage: 0.85), .noTrainingMax),
            (.percentOfE1RM(percentage: 0.85), .noEstimatedOneRepMax),
            (.percentOfTopSet(percentage: 0.85), .noTopSet),
            (.previousPlusIncrement(Increments.twoAndAHalfKilograms), .noPreviousPerformance),
            (.rpeTarget(rpe: 8), .noEstimatedOneRepMax),
        ]
        for (prescription, reason) in expected {
            #expect(resolver.resolve(prescription, in: empty) == .unresolvable(reason))
        }
        // The three cases that need nothing from a context still answer in an empty one.
        #expect(
            resolver.resolve(.fixedWeight(Weight(grams: 100_000)), in: empty)
                == .resolved(ResolvedPrescription(target: Weight(grams: 100_000))))
        #expect(
            resolver.resolve(.bodyweight(added: .zero), in: empty)
                == .resolved(ResolvedPrescription(target: .zero)))
        #expect(resolver.resolve(.amrap, in: empty) == .unspecifiedLoad)
    }

    @Test("Supplying the missing input resolves the very same prescription")
    func supplyingTheInputResolvesIt() throws {
        let basis = Weight(grams: 100_000)
        // A factor of 1 and a rule that cannot round, so each answer is the input that was added.
        let supplied: [(Prescription, PrescriptionContext)] = [
            (
                .percentOfTrainingMax(percentage: 1),
                try prescriptionContext(
                    increment: Increments.oneGram, trainingMax: prescribedTrainingMax(100_000))
            ),
            (
                .percentOfE1RM(percentage: 1),
                try prescriptionContext(increment: Increments.oneGram, estimate: basis)
            ),
            (
                .percentOfTopSet(percentage: 1),
                try prescriptionContext(increment: Increments.oneGram, topSet: basis)
            ),
            (
                .previousPlusIncrement(.zero),
                try prescriptionContext(increment: Increments.oneGram, previous: basis)
            ),
        ]
        for (prescription, context) in supplied {
            #expect(
                resolver.resolve(prescription, in: context)
                    == .resolved(ResolvedPrescription(target: basis)))
        }
    }

    @Test("A rep count is missing only for an RPE target, and only after the estimate is there")
    func anRPETargetNeedsARepCount() throws {
        let estimate = Weight(grams: 200_000)
        #expect(
            resolver.resolve(.rpeTarget(rpe: 8), in: try prescriptionContext(estimate: estimate))
                == .unresolvable(.noRepCount))
        // A slot expressing a rep range has to pick one; with a count, the same call answers.
        #expect(
            resolver.resolve(
                .rpeTarget(rpe: 8), in: try prescriptionContext(estimate: estimate, reps: 5))
                == .resolved(ResolvedPrescription(target: Weight(grams: 162_500))))
        // No other case reads it: the same rep-less context resolves a percentage of the estimate.
        #expect(
            resolver.resolve(
                .percentOfE1RM(percentage: 1),
                in: try prescriptionContext(increment: Increments.oneGram, estimate: estimate))
                == .resolved(ResolvedPrescription(target: estimate)))
    }

    @Test("The basis is looked for before the values that scale it")
    func theMissingInputWinsOverAnImpossibleValue() throws {
        // Which prompt appears is a real user-facing consequence, so the precedence is pinned:
        // there is nothing to take a percentage *of* until the basis exists.
        let empty = try prescriptionContext()
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 0), in: empty)
                == .unresolvable(.noTrainingMax))
        #expect(
            resolver.resolve(.rpeTarget(rpe: 47), in: empty) == .unresolvable(.noEstimatedOneRepMax))
        // With a basis present, the impossible value is what is named.
        let withBasis = try prescriptionContext(
            trainingMax: prescribedTrainingMax(100_000), estimate: Weight(grams: 200_000), reps: 5)
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 0), in: withBasis)
                == .unresolvable(.percentageOutOfRange(0)))
        #expect(
            resolver.resolve(.rpeTarget(rpe: 47), in: withBasis) == .unresolvable(.rpeOutOfRange(47)))
    }

    @Test("An RPE target names its own bad value before it names the slot's")
    func thePrescriptionsOwnValueIsNamedBeforeTheContexts() throws {
        // Three of the five RPE refusals can apply at once, and which one a lifter is shown is a
        // user-facing consequence rather than an implementation detail — so the order is pinned.
        // Without this, permuting these guards changes the prompt and fails nothing.
        let estimate = Weight(grams: 200_000)
        #expect(
            resolver.resolve(.rpeTarget(rpe: 47), in: try prescriptionContext(estimate: estimate))
                == .unresolvable(.rpeOutOfRange(47)))
        #expect(
            resolver.resolve(
                .rpeTarget(rpe: 47), in: try prescriptionContext(estimate: estimate, reps: 99))
                == .unresolvable(.rpeOutOfRange(47)))
        // And with the RPE legal, the two slot-side refusals order the way the guards read.
        #expect(
            resolver.resolve(
                .rpeTarget(rpe: 8), in: try prescriptionContext(estimate: estimate, reps: 99))
                == .unresolvable(.repCountOutOfRange(99)))
    }
}

/// The percentage a refusal named, or `nil` when it refused for another reason.
///
/// Needed because a `NaN` payload makes a reason that does not equal itself, so the refusals
/// carrying one cannot be asserted by comparing whole values.
private func percentageRefused(_ resolution: PrescriptionResolution) -> Double? {
    guard case .unresolvable(.percentageOutOfRange(let percentage)) = resolution else { return nil }
    return percentage
}

/// The RPE a refusal named, or `nil` when it refused for another reason. See above.
private func rpeRefused(_ resolution: PrescriptionResolution) -> Double? {
    guard case .unresolvable(.rpeOutOfRange(let rpe)) = resolution else { return nil }
    return rpe
}

@Suite("Prescription resolution — values that cannot produce a weight")
struct PrescriptionResolverImpossibleValueTests {
    private let resolver = PrescriptionResolver()

    @Test(
        "A percentage that is not finite and positive is named, whichever case carries it",
        arguments: [0.0, -0.5, .infinity, -.infinity])
    func percentagesThatCannotScaleAreNamed(percentage: Double) throws {
        let context = try prescriptionContext(
            trainingMax: prescribedTrainingMax(100_000),
            estimate: Weight(grams: 200_000),
            topSet: Weight(grams: 150_000))
        let cases: [Prescription] = [
            .percentOfTrainingMax(percentage: percentage),
            .percentOfE1RM(percentage: percentage),
            .percentOfTopSet(percentage: percentage),
        ]
        for prescription in cases {
            #expect(
                resolver.resolve(prescription, in: context)
                    == .unresolvable(.percentageOutOfRange(percentage)))
        }
    }

    @Test("A percentage above 1 is not refused — a peaking block is not an error")
    func aPercentageAboveOneResolves() throws {
        let context = try prescriptionContext(
            increment: Increments.oneGram, trainingMax: prescribedTrainingMax(100_000))
        #expect(
            resolver.resolve(.percentOfTrainingMax(percentage: 1.1), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 110_000))))
    }

    @Test(
        "An RPE outside the scale is named",
        arguments: [0.0, 0.9, 10.5, 11.0, .infinity, -.infinity])
    func anRPEOutsideTheScaleIsNamed(rpe: Double) throws {
        let context = try prescriptionContext(estimate: Weight(grams: 200_000), reps: 5)
        #expect(SetRecord.rpeRange.contains(rpe) == false)
        #expect(
            resolver.resolve(.rpeTarget(rpe: rpe), in: context) == .unresolvable(.rpeOutOfRange(rpe)))
    }

    @Test("A refusal carrying a NaN is a value that does not equal itself")
    func aNaNRefusalCannotBeComparedForEquality() throws {
        // `Prescription` validates nothing at construction, so a `NaN` reaches resolution and is
        // carried back out in the reason — where `Double`'s equality is the one in play. The
        // refusal is real and correct; only comparing two of them fails, which is why every
        // assertion about a `NaN` payload destructures instead.
        let context = try prescriptionContext(
            trainingMax: prescribedTrainingMax(100_000), estimate: Weight(grams: 200_000), reps: 5)
        let percentage = resolver.resolve(.percentOfTrainingMax(percentage: .nan), in: context)
        #expect(percentageRefused(percentage)?.isNaN == true)
        #expect(percentage != .unresolvable(.percentageOutOfRange(.nan)))
        let rpe = resolver.resolve(.rpeTarget(rpe: .nan), in: context)
        #expect(rpeRefused(rpe)?.isNaN == true)
        #expect(SetRecord.rpeRange.contains(Double.nan) == false)
    }

    @Test("A rep count off the chart's rep axis is named", arguments: [0, -1, 11, 12])
    func aRepCountOffTheAxisIsNamed(reps: Int) throws {
        let context = try prescriptionContext(estimate: Weight(grams: 200_000), reps: reps)
        #expect(RPETable.standard.repRange.contains(reps) == false)
        #expect(
            resolver.resolve(.rpeTarget(rpe: 8), in: context) == .unresolvable(.repCountOutOfRange(reps)))
    }

    @Test("A legal effort the chart has no cell for is a different refusal from a legal rep count")
    func anEffortOffTheChartIsNotARepCountRefusal() throws {
        // Ten reps at RPE 5 is fifteen reps from failure, past the end of the chart — while ten
        // reps is inside its rep axis and RPE 5 is inside the scale. Both other refusals would be
        // the wrong sentence: nothing is out of range, the chart simply stops.
        let context = try prescriptionContext(
            increment: Increments.oneGram, estimate: Weight(grams: 200_000), reps: 10)
        #expect(RPETable.standard.repRange.contains(10))
        #expect(SetRecord.rpeRange.contains(5))
        #expect(
            resolver.resolve(.rpeTarget(rpe: 5), in: context)
                == .unresolvable(.effortOffTheChart(reps: 10, rpe: 5)))
        // The same rep count two RPE points higher is twelve from failure, which the chart holds
        // at 0.680 — and 0.680 × 200 000 is 136 000.
        #expect(
            resolver.resolve(.rpeTarget(rpe: 8), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 136_000))))
    }

    @Test("A weight that will not fit in Int grams is refused rather than trapping")
    func anUnrepresentableWeightIsRefused() throws {
        let absurd = Weight(grams: .max)
        #expect(
            resolver.resolve(
                .percentOfTrainingMax(percentage: 2),
                in: try prescriptionContext(trainingMax: TrainingMax(weight: absurd, sourceWeight: absurd)))
                == .unresolvable(.notRepresentable))
        // The RPE path reaches the same guard: the chart's top cell is a factor of 1, and even that
        // does not fit, because `Double(Int.max)` rounds up to 2^63.
        #expect(
            resolver.resolve(
                .rpeTarget(rpe: 10), in: try prescriptionContext(estimate: absurd, reps: 1))
                == .unresolvable(.notRepresentable))
        // And the one addition in the module that would otherwise trap.
        #expect(
            resolver.resolve(
                .previousPlusIncrement(Weight(grams: 1)),
                in: try prescriptionContext(previous: absurd)) == .unresolvable(.notRepresentable))
    }
}

@Suite("Prescription resolution — the sign of the basis")
struct PrescriptionResolverSignTests {
    private let resolver = PrescriptionResolver()

    @Test("A percentage of assisted work is refused, and every factor-taking case meets one guard")
    func aPercentageOfANegativeBasisIsRefused() throws {
        // 80% of 20 kg of assistance is 16 kg of assistance — a backoff set that comes out harder
        // than the set it backs off from. The boundary is `< 0`, matching `E1RMCalculator`'s and
        // `TrainingMaxResolver`'s, so the module holds one sign rule rather than three.
        let assisted = Weight(grams: -20_000)
        let context = try prescriptionContext(
            trainingMax: TrainingMax(weight: assisted, sourceWeight: assisted),
            estimate: assisted,
            topSet: assisted,
            reps: 5)
        let cases: [Prescription] = [
            .percentOfTrainingMax(percentage: 0.8),
            .percentOfE1RM(percentage: 0.8),
            .percentOfTopSet(percentage: 0.8),
            .rpeTarget(rpe: 8),
        ]
        for prescription in cases {
            #expect(
                resolver.resolve(prescription, in: context) == .unresolvable(.negativeBasis(assisted)))
        }
    }

    @Test("Zero is a basis and not an absence")
    func aZeroBasisResolvesToZero() throws {
        // The boundary is below zero. A prescription of zero is useless and not backwards, and
        // `FR-2.3.5` needs it to stay distinguishable from having no training max at all.
        let context = try prescriptionContext(trainingMax: prescribedTrainingMax(0))
        let resolution = resolver.resolve(.percentOfTrainingMax(percentage: 0.85), in: context)
        #expect(resolution == .resolved(ResolvedPrescription(target: .zero)))
        #expect(resolution != .unresolvable(.noTrainingMax))
        #expect(resolution != .unresolvable(.negativeBasis(.zero)))
    }

    @Test("An increment on assisted work resolves, because a step keeps its direction")
    func anIncrementOnAssistedWorkIsNotRefused() throws {
        // Deliberately the opposite answer to the percentages above: adding 2.5 kg to 20 kg of
        // assistance leaves 17.5 kg of assistance, which is what progressing assisted work means.
        // A percentage of the same load moves it the other way.
        let context = try prescriptionContext(previous: Weight(grams: -20_000))
        #expect(
            resolver.resolve(.previousPlusIncrement(Increments.twoAndAHalfKilograms), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: -17_500))))
        // Bodyweight work is the same reading one case over: the added load is the prescription.
        #expect(
            resolver.resolve(.bodyweight(added: Weight(grams: -20_000)), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: -20_000))))
    }
}
