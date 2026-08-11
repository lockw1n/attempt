import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## What is being asserted here
//
// `TR-0.2.12` wants an unresolvable prescription to trace as far as the point of failure, and every
// refusal below is asserted as a *whole* step list beside the reason it produced. The two are read
// together on purpose: the trace says how far the chain got and the resolution says what stopped it,
// so no step kind restates a reason and no reason has to be inferred from a trace's length.
//
// **The split is by what had already been computed, not by the kind of refusal.** A missing input
// usually means nothing ran, but `.noRepCount` is looked for *after* the estimate has been read, so
// it refuses with a basis in hand — and `notRepresentable` reaches three different lengths depending
// on which of the three places it fires in. Grouping the twelve as "missing means empty" would be
// wrong about both.

/// One refusal to check: what was asked, in what situation, what it answered, and the single step
/// the trace should be left holding.
private struct RefusalCase {
    let prescription: Prescription
    let context: PrescriptionContext
    let reason: PrescriptionUnresolvedReason
    let step: ResolutionStep
}

@Suite("Resolution trace — how far a refusal got")
struct PrescriptionRefusalTraceTests {
    private let resolver = PrescriptionResolver()

    @Test("A basis that is absent traces nothing at all")
    func anAbsentBasisTracesNothing() throws {
        // Four of the five missing-input refusals: the basis is the first thing looked for, so
        // nothing has been computed and there is nothing honest to show.
        let empty = try prescriptionContext()
        let missing: [(Prescription, PrescriptionUnresolvedReason)] = [
            (.percentOfTrainingMax(percentage: 0.85), .noTrainingMax),
            (.percentOfE1RM(percentage: 0.85), .noEstimatedOneRepMax),
            (.percentOfTopSet(percentage: 0.85), .noTopSet),
            (.previousPlusIncrement(Increments.twoAndAHalfKilograms), .noPreviousPerformance),
            (.rpeTarget(rpe: 8), .noEstimatedOneRepMax),
        ]
        for (prescription, reason) in missing {
            let traced = resolver.traced(prescription, in: empty)
            #expect(traced.resolution == .unresolvable(reason))
            #expect(traced.trace == .empty)
        }
    }

    @Test("A missing rep count traces the basis, unlike the other four missing inputs")
    func aMissingRepCountTracesTheBasisItAlreadyRead() throws {
        // The one that crosses the two groups. An RPE target reads the estimate before it looks for
        // a rep count, so "the slot gives no single rep count" arrives with a chain already started
        // — and a lifter sees the estimate the target would have been taken from.
        let estimate = Weight(grams: 200_000)
        let traced = resolver.traced(.rpeTarget(rpe: 8), in: try prescriptionContext(estimate: estimate))
        #expect(traced.resolution == .unresolvable(.noRepCount))
        #expect(traced.trace.steps == [.basis(.estimatedOneRepMax, estimate)])
    }

    @Test("An impossible value traces the basis that was already read, never more")
    func anImpossibleValueTracesTheBasis() throws {
        // The basis is read before the prescription's own value is judged, so each of these refuses
        // with exactly one step. Nothing was scaled, so no `scaled` step exists to show.
        let estimate = Weight(grams: 200_000)
        let cases = [
            RefusalCase(
                prescription: .percentOfTrainingMax(percentage: 0),
                context: try prescriptionContext(trainingMax: prescribedTrainingMax(100_000)),
                reason: .percentageOutOfRange(0),
                step: .basis(.trainingMax, Weight(grams: 100_000))),
            RefusalCase(
                prescription: .percentOfTopSet(percentage: 0.85),
                context: try prescriptionContext(topSet: Weight(grams: -20_000)),
                reason: .negativeBasis(Weight(grams: -20_000)),
                step: .basis(.topSet, Weight(grams: -20_000))),
            RefusalCase(
                prescription: .rpeTarget(rpe: 47),
                context: try prescriptionContext(estimate: estimate, reps: 5),
                reason: .rpeOutOfRange(47),
                step: .basis(.estimatedOneRepMax, estimate)),
            RefusalCase(
                prescription: .rpeTarget(rpe: 8),
                context: try prescriptionContext(estimate: estimate, reps: 47),
                reason: .repCountOutOfRange(47),
                step: .basis(.estimatedOneRepMax, estimate)),
        ]
        for expected in cases {
            let traced = resolver.traced(expected.prescription, in: expected.context)
            #expect(traced.resolution == .unresolvable(expected.reason))
            #expect(traced.trace.steps == [expected.step])
        }
    }

    @Test("An effort off the chart traces the basis and no chart step")
    func anEffortOffTheChartTracesNoChartStep() throws {
        // Ten reps at RPE 1 is nineteen reps from failure: both inputs are inside their ranges and
        // the standard chart, which stops at 13.5, has no cell. The chart *was* consulted and gave
        // nothing, so there is no step to show — a chart step with no fraction would be describing a
        // lookup that produced nothing. The reason carries both inputs, and the key is their sum.
        let estimate = Weight(grams: 200_000)
        let traced = resolver.traced(
            .rpeTarget(rpe: 1), in: try prescriptionContext(estimate: estimate, reps: 10))
        #expect(traced.resolution == .unresolvable(.effortOffTheChart(reps: 10, rpe: 1)))
        #expect(traced.trace.steps == [.basis(.estimatedOneRepMax, estimate)])

        // A legal effort on the same chart does produce the step, so the absence is the refusal
        // rather than the chart step never being emitted at all.
        let onTheChart = resolver.traced(
            .rpeTarget(rpe: 8), in: try prescriptionContext(estimate: estimate, reps: 10))
        #expect(
            onTheChart.trace.steps.count == 4,
            "an effort the chart answers should trace basis, effort, scaled and rounded")
    }

    @Test("A weight that will not fit traces however far it got, in each of its three places")
    func anUnrepresentableWeightTracesWhatRanBeforeIt() throws {
        // One reason, three different chain lengths, because it fires at three different depths.
        let absurd = Weight(grams: .max)

        let scaling = resolver.traced(
            .percentOfTrainingMax(percentage: 2),
            in: try prescriptionContext(
                trainingMax: TrainingMax(weight: absurd, sourceWeight: absurd)))
        #expect(scaling.resolution == .unresolvable(.notRepresentable))
        #expect(scaling.trace.steps == [.basis(.trainingMax, absurd)])

        // Deeper: the chart answered first, so the effort step survives into the refusal. Two steps,
        // which only an RPE target can reach — see `aRefusalAfterTheChartKeepsTheChartStep` for the
        // other reason that gets there.
        let afterTheChart = resolver.traced(
            .rpeTarget(rpe: 10), in: try prescriptionContext(estimate: absurd, reps: 1))
        #expect(afterTheChart.resolution == .unresolvable(.notRepresentable))
        #expect(
            afterTheChart.trace.steps == [
                .basis(.estimatedOneRepMax, absurd),
                .effort(reps: 1, rpe: 10, repsToFailure: 1, fractionOfMax: 1),
            ])

        // And the one addition in the module that would otherwise trap.
        let adding = resolver.traced(
            .previousPlusIncrement(Weight(grams: 1)), in: try prescriptionContext(previous: absurd))
        #expect(adding.resolution == .unresolvable(.notRepresentable))
        #expect(adding.trace.steps == [.basis(.previousPerformance, absurd)])
    }

    @Test("A refusal reached after the chart keeps the chart step")
    func aRefusalAfterTheChartKeepsTheChartStep() throws {
        // The second of the two two-step refusals, and the one the guard order makes reachable: the
        // sign of the basis is checked where the factor is applied, which is *after* the chart has
        // been read. So assisted work under an RPE target refuses with the lookup already in the
        // trace — correctly, since the chart really was consulted.
        let assisted = Weight(grams: -20_000)
        let traced = resolver.traced(
            .rpeTarget(rpe: 8), in: try prescriptionContext(estimate: assisted, reps: 5))
        #expect(traced.resolution == .unresolvable(.negativeBasis(assisted)))
        #expect(
            traced.trace.steps == [
                .basis(.estimatedOneRepMax, assisted),
                .effort(reps: 5, rpe: 8, repsToFailure: 7, fractionOfMax: 0.811),
            ])
        // A percentage of the same assisted load refuses one step earlier, because no chart is read on
        // that path. The pair is what shows the trace's length tracks the guard order rather than the
        // reason.
        #expect(
            resolver.traced(.percentOfE1RM(percentage: 0.85), in: try prescriptionContext(estimate: assisted))
                .trace.steps == [.basis(.estimatedOneRepMax, assisted)])
    }

    @Test("The two cases that compute nothing trace nothing, and are not the same answer")
    func theCasesThatComputeNothingTraceNothing() throws {
        // An empty trace says only that no operation over a weight was performed. Which of the
        // several reasons for that it was belongs to the resolution, so these two share a trace and
        // must not be told apart by it.
        let full = try fullContext()
        let unrecognised = try #require(
            UnrecognisedPrescription(
                kind: "wavePercent", schemaVersion: 2, payload: ["weight": .int(102_500)]))

        let amrap = resolver.traced(.amrap, in: full)
        #expect(amrap.resolution == .unspecifiedLoad)
        #expect(amrap.trace == .empty)

        let newer = resolver.traced(.unrecognised(unrecognised), in: full)
        #expect(newer.resolution == .unresolvable(.unrecognisedPrescription(kind: "wavePercent")))
        #expect(newer.trace == .empty)

        // An empty context changes neither answer, which is the other half of it: AMRAP consults
        // nothing and an unrecognised prescription's payload is never read, so there is nothing for a
        // context to supply or withhold.
        let empty = try prescriptionContext()
        #expect(resolver.traced(.amrap, in: empty).trace == .empty)
        #expect(resolver.traced(.unrecognised(unrecognised), in: empty).trace == .empty)
        #expect(resolver.traced(.amrap, in: empty).resolution == amrap.resolution)
        #expect(resolver.traced(.unrecognised(unrecognised), in: empty).resolution == newer.resolution)
        #expect(amrap.trace == newer.trace)
        #expect(amrap.resolution != newer.resolution)
    }

    @Test("Every refusal that reads a basis puts that basis in the trace, and stops there")
    func noRefusalTracesPastItsBasis() throws {
        // Systematic rather than case by case: a refusal must never carry a step for an operation
        // downstream of where it stopped. The one exception is the chart lookup, which precedes the
        // scaling guard — so a refusal traces at most a basis and at most one chart step.
        let contexts = [
            try fullContext(),
            try prescriptionContext(),
            try prescriptionContext(topSet: Weight(grams: -20_000)),
            try prescriptionContext(estimate: Weight(grams: 200_000), reps: 47),
        ]
        var refusals = 0
        for context in contexts {
            for prescription in try everyPrescription() + impossiblePrescriptions() {
                let traced = resolver.traced(prescription, in: context)
                guard case .unresolvable = traced.resolution else { continue }
                refusals += 1
                #expect(traced.trace.steps.count <= 2)
                for step in traced.trace.steps {
                    switch step {
                    case .basis, .effort:
                        break
                    case .scaled, .incremented, .rounded, .loaded:
                        Issue.record("a refusal traced \(step), which is past where it stopped")
                    }
                }
            }
        }
        // Anchored: the loop must actually meet refusals, or it asserts nothing whatsoever. Five in
        // the full context (the unknown type, and the four impossible values), ten in the empty one,
        // ten where only a negative top set is present, and nine where only an off-axis rep count is.
        #expect(refusals == 34)
    }
}

/// Prescriptions whose own values cannot produce a weight, for the sweep above.
private func impossiblePrescriptions() -> [Prescription] {
    [
        .percentOfTrainingMax(percentage: .nan),
        .percentOfE1RM(percentage: 0),
        .percentOfTopSet(percentage: -0.5),
        .rpeTarget(rpe: 47),
    ]
}

@Suite("Resolution trace — how far a training max refusal got")
struct TrainingMaxRefusalTraceTests {
    private let resolver = TrainingMaxResolver(.epley)

    @Test("A source that could not be read traces nothing")
    func anUnreadableSourceTracesNothing() throws {
        // Both of these are decided before any weight exists: an empty log yields no record, and an
        // out-of-range N is refused without consulting the log at all.
        let noEstimate = resolver.traced(try tracedRefusalConfiguration(.percentOfE1RM), from: [])
        #expect(noEstimate.resolution == .unresolvable(.noSourceData))
        #expect(noEstimate.trace == .empty)

        let log = [try workingSet(Weight(grams: 110_000), reps: 2)]
        let noSuchRepMax = resolver.traced(
            try tracedRefusalConfiguration(.percentOfRepMax(reps: 5)), from: log)
        #expect(noSuchRepMax.resolution == .unresolvable(.noSourceData))
        #expect(noSuchRepMax.trace == .empty)

        let outOfRange = resolver.traced(
            try tracedRefusalConfiguration(.percentOfRepMax(reps: 47)), from: log)
        #expect(outOfRange.resolution == .unresolvable(.repCountOutOfRange(47)))
        #expect(outOfRange.trace == .empty)
    }

    @Test("A source that was read and then refused traces the source")
    func aRefusedSourceStillTracesIt() throws {
        // Assisted work: the number is real and was read, and the refusal is about what a percentage
        // of it would mean. Showing the weight is the point — it is what the prompt is about.
        let assisted = Weight(grams: -20_000)
        let negative = resolver.traced(try tracedRefusalConfiguration(.manual(assisted)), from: [])
        #expect(negative.resolution == .unresolvable(.negativeSourceWeight(assisted)))
        #expect(negative.trace.steps == [.basis(.entered, assisted)])

        // And the product that will not fit, which is refused one step later than the sign is.
        let absurd = Weight(grams: .max)
        let overflow = resolver.traced(
            try tracedRefusalConfiguration(.percentOfRepMax(reps: 1), percentage: 2),
            from: [try workingSet(absurd, reps: 1)])
        #expect(overflow.resolution == .unresolvable(.notRepresentable))
        #expect(overflow.trace.steps == [.basis(.repMax(reps: 1), absurd)])
    }
}

/// Builds a configuration for the refusals above, failing the test rather than force unwrapping.
private func tracedRefusalConfiguration(
    _ source: TrainingMaxSource, percentage: Double = 0.9
) throws -> TrainingMaxConfiguration {
    try #require(
        TrainingMaxConfiguration(
            source: source,
            percentage: percentage,
            rounding: try roundingRule(Increments.twoAndAHalfKilograms, .nearest),
            progressionIncrement: nil))
}
