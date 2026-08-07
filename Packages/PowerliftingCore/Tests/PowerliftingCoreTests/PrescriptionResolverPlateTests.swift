import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## The decision this file exists to pin
//
// `FR-2.3.3` says a resolved weight respects both the rounding rule and the equipment profile, and
// does not say which of them decides the number. Applying both in sequence is the one answer that
// is wrong: snapping to a 5 kg step and *then* asking what loads discards a weight the gym's
// 1.25 kg pair puts on the bar precisely. So the rule decides and the inventory describes — and the
// price of the other order is asserted here rather than argued, on a gym that loads 82.5 kg exactly
// and cannot load 85 kg at all.
//
// The corollary is `FR-1.4.4`: because the target is never moved onto a loadable weight, a target
// that does not load still has a nearest above and below to show. A resolver that snapped to the
// inventory would leave `FR-1.4.4` with nothing to display for any prescribed weight.

/// One prescription of every type, including the ninth that only a decoder produces.
///
/// Anchored by `theseAreEveryPrescriptionType`, so a type dropped from this list fails a test
/// rather than quietly taking its assertions with it.
private func everyPrescription() throws -> [Prescription] {
    [
        .fixedWeight(Weight(grams: 100_000)),
        .percentOfTrainingMax(percentage: 0.85),
        .percentOfE1RM(percentage: 0.75),
        .percentOfTopSet(percentage: 0.9),
        .rpeTarget(rpe: 8),
        .amrap,
        .previousPlusIncrement(Increments.twoAndAHalfKilograms),
        .bodyweight(added: Weight(grams: 20_000)),
        .unrecognised(
            try #require(UnrecognisedPrescription(kind: "wavePercent", schemaVersion: 2))),
    ]
}

/// A context in which every case above resolves.
private func fullContext() throws -> PrescriptionContext {
    try prescriptionContext(
        trainingMax: prescribedTrainingMax(100_000),
        estimate: Weight(grams: 200_000),
        topSet: Weight(grams: 150_000),
        previous: Weight(grams: 140_000),
        reps: 5,
        plates: try sparsePlateGym())
}

@Suite("Prescription resolution — the rule decides, the plates describe")
struct PrescriptionResolverPlateTests {
    private let resolver = PrescriptionResolver()

    @Test("A coarse rule moves the target off a weight the gym loads exactly, and says so")
    func theRuleDecidesTheNumberAndThePlatesOnlyDescribeIt() throws {
        let gym = try sparsePlateGym()
        // 110 000 × 0.75 = 82 500, which is 20 kg of bar plus 15 + 15 + 1.25 a side.
        let loadable = PlateLoading(
            totalWeight: Weight(grams: 82_500),
            perSide: [
                PlateCount(plate: Weight(grams: 15_000), count: 2),
                PlateCount(plate: Weight(grams: 1_250), count: 1),
            ])

        let unrounded = try #require(
            resolvedPrescription(
                resolver.resolve(
                    .percentOfE1RM(percentage: 0.75),
                    in: try prescriptionContext(
                        increment: Increments.oneGram,
                        estimate: Weight(grams: 110_000),
                        plates: gym))))
        #expect(unrounded.target == Weight(grams: 82_500))
        #expect(unrounded.loading == .exact(loadable))

        // The same prescription under a 5 kg rule: 82 500 is 16.5 steps, so the target becomes
        // 85 000 — and 32.5 kg a side is exactly what this gym's single 1.25 pair cannot reach.
        let rounded = try #require(
            resolvedPrescription(
                resolver.resolve(
                    .percentOfE1RM(percentage: 0.75),
                    in: try prescriptionContext(
                        increment: Weight(grams: 5_000),
                        estimate: Weight(grams: 110_000),
                        plates: gym))))
        #expect(rounded.target == Weight(grams: 85_000))
        guard case .nearest(let below, let above)? = rounded.loading else {
            Issue.record("a target of 85 000 g should not load on this gym")
            return
        }
        #expect(below == loadable)
        #expect(above?.totalWeight == Weight(grams: 90_000))
    }

    @Test("A target the gym cannot load is reported, never replaced")
    func anUnloadableTargetIsReportedRatherThanReplaced() throws {
        // 90 000 × 0.9 = 81 000, already a multiple of the 500 g rule, and 30.5 kg a side is not a
        // sum this inventory reaches. `FR-1.4.4` wants both neighbours; the target stays put.
        let resolved = try #require(
            resolvedPrescription(
                resolver.resolve(
                    .percentOfE1RM(percentage: 0.9),
                    in: try prescriptionContext(
                        increment: Weight(grams: 500),
                        estimate: Weight(grams: 90_000),
                        plates: try sparsePlateGym()))))
        #expect(resolved.target == Weight(grams: 81_000))
        guard case .nearest(let below, let above)? = resolved.loading else {
            Issue.record("a target of 81 000 g should not load on this gym")
            return
        }
        #expect(below?.totalWeight == Weight(grams: 80_000))
        #expect(above?.totalWeight == Weight(grams: 82_500))
    }

    @Test("With no equipment profile the weight resolves and carries no loading")
    func withNoProfileTheTargetStandsAlone() throws {
        // An absent profile is not a refusal: the target is a complete answer without it, and the
        // number does not depend on which gym the lifter is standing in.
        let context = try prescriptionContext(
            increment: Weight(grams: 5_000), estimate: Weight(grams: 110_000))
        #expect(
            resolver.resolve(.percentOfE1RM(percentage: 0.75), in: context)
                == .resolved(ResolvedPrescription(target: Weight(grams: 85_000))))
    }

    @Test("Every loading returned belongs to the target beside it")
    func theLoadingIsTheResolvedTargetsOwn() throws {
        // The mutation this closes: computing the loading for the *unrounded* weight, which agrees
        // with the target whenever the rule happens not to move it.
        let gym = try sparsePlateGym()
        let context = try fullContext()
        var checked = 0
        for prescription in try everyPrescription() {
            guard let resolved = resolvedPrescription(resolver.resolve(prescription, in: context)) else {
                continue
            }
            checked += 1
            if case .bodyweight = prescription {
                #expect(resolved.loading == nil)
            } else {
                #expect(resolved.loading == gym.loading(for: resolved.target))
            }
        }
        // Anchored, or the loop asserts nothing at all the moment resolution stops resolving —
        // seven of the nine types answer with a weight here, and `.amrap` and `.unrecognised` do not.
        #expect(checked == 7)
    }
}

@Suite("Prescription resolution — determinism")
struct PrescriptionResolverDeterminismTests {
    private let resolver = PrescriptionResolver()

    @Test("These are every prescription type")
    func theseAreEveryPrescriptionType() throws {
        let prescriptions = try everyPrescription()
        // As a set, so two fixtures of one type cannot stand in for a missing one.
        #expect(Set(prescriptions.compactMap(\.kind)) == Set(PrescriptionKind.allCases))
        #expect(prescriptions.filter { $0.kind == nil }.count == 1)
    }

    @Test("The same inputs give the same answer, every case, every run")
    func resolvingTwiceGivesTheSameAnswer() throws {
        // Two contexts built separately rather than one reused, so a resolver reading anything
        // outside its arguments — an iteration order, a cached value — shows up as a difference.
        let context = try fullContext()
        let again = try fullContext()
        for prescription in try everyPrescription() {
            let first = resolver.resolve(prescription, in: context)
            #expect(first == resolver.resolve(prescription, in: context))
            #expect(first == resolver.resolve(prescription, in: again))
            // Anchored: at least one of the two is a real answer rather than both being nothing.
            #expect(first != .unresolvable(.notRepresentable))
        }
    }

    @Test("Every case in a full context resolves, or names the one thing it cannot be given")
    func aFullContextLeavesNothingUnresolvedExceptTheUnknownType() throws {
        let context = try fullContext()
        for prescription in try everyPrescription() {
            let resolution = resolver.resolve(prescription, in: context)
            switch prescription {
            case .amrap:
                #expect(resolution == .unspecifiedLoad)
            case .unrecognised(let unrecognised):
                #expect(
                    resolution == .unresolvable(.unrecognisedPrescription(kind: unrecognised.kind)))
            default:
                #expect(resolvedPrescription(resolution) != nil)
            }
        }
    }
}
