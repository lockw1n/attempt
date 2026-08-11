import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## What is being asserted here
//
// `FR-2.3.4` calls an untraceable number untrustworthy, so these assertions compare **whole step
// lists** against literals rather than spot-checking one step. Every figure is arithmetic written
// beside it: a basis, a factor, an increment, or one of the standard chart's own cells.
//
// Two tests carry the requirement between them.
// `theFullChainIsTheFiveLinksTheRequirementNames` joins both resolvers' traces and asserts all seven
// steps of `e1RM → TM → % → rounded → plates`, including **both** roundings — a prescribed weight is
// two of them away from the estimate, and a trace showing one leaves a 500 g discrepancy with
// nothing to explain it. `theEnteredWeightCasesTraceNoRoundingStep` asserts the converse: three
// cases apply no rule, and a trace rendering one for them would describe an operation that never
// ran.
//
// Contiguity is checked structurally rather than described. `expectContiguous` walks a trace and
// fails unless every step that reads a weight reads the last weight the trace produced, which is
// what makes the plate step provably the *final* target's rather than the unrounded one's.

// MARK: - Fixtures

/// The weight a step reads, or `nil` for a step that reads none: a basis starts a chain, and a
/// chart lookup consumes reps and an RPE rather than a weight.
private func consumedWeight(_ step: ResolutionStep) -> Weight? {
    switch step {
    case .basis: nil
    case .scaled(_, let from, _): from
    case .effort: nil
    case .incremented(_, let from, _): from
    case .rounded(_, let from, _): from
    case .loaded(let target, _): target
    }
}

/// Fails unless every step that reads a weight reads the last weight the trace produced.
///
/// - Returns: How many steps read one, so a caller can anchor the walk — a resolver that stopped
///   emitting steps would otherwise satisfy this by having nothing to check.
@discardableResult
private func expectContiguous(_ trace: ResolutionTrace, _ label: String) -> Int {
    var standing: Weight?
    var checked = 0
    for (offset, step) in trace.steps.enumerated() {
        guard let consumed = consumedWeight(step) else {
            if let produced = step.resultingWeight { standing = produced }
            continue
        }
        checked += 1
        #expect(
            consumed == standing,
            Comment(rawValue: "\(label): step \(offset) reads \(consumed.grams) g"))
        if let produced = step.resultingWeight { standing = produced }
    }
    return checked
}

/// Builds a training max configuration, failing the test rather than force unwrapping.
private func tracedConfiguration(
    _ source: TrainingMaxSource,
    percentage: Double = 0.9,
    increment: Weight = Increments.twoAndAHalfKilograms
) throws -> TrainingMaxConfiguration {
    try #require(
        TrainingMaxConfiguration(
            source: source,
            percentage: percentage,
            rounding: try roundingRule(increment, .nearest),
            progressionIncrement: nil))
}

/// One 110 kg double, which Epley estimates at 117 333 g and Brzycki at 113 143 g — the figures
/// `PersonalRecordCalculatorTests` pins — and which holds the 1RM and 2RM at 110 000 g.
private func tracedLog() throws -> [SetRecord] {
    [try workingSet(Weight(grams: 110_000), reps: 2)]
}

// MARK: - The chain the requirement names

@Suite("Resolution trace — the chain FR-2.3.4 names")
struct ResolutionChainTests {
    @Test("Both resolvers' traces join into e1RM, training max, percentage, rounding and plates")
    func theFullChainIsTheFiveLinksTheRequirementNames() throws {
        let rule = try roundingRule(Increments.twoAndAHalfKilograms, .nearest)

        // 117 333 × 0.9 = 105 600, which is 42.24 steps of 2.5 kg, so the rule takes 600 g off.
        let firstHalf = TrainingMaxResolver(.epley).traced(
            try tracedConfiguration(.percentOfE1RM), from: try tracedLog())
        guard case .resolved(let trainingMax) = firstHalf.resolution else {
            Issue.record("the training max should resolve")
            return
        }
        #expect(
            trainingMax
                == TrainingMax(weight: Weight(grams: 105_000), sourceWeight: Weight(grams: 117_333)))

        // The resolved value itself is handed on, so the two halves are demonstrably about one
        // number rather than two literals that happen to agree.
        // 105 000 × 0.85 = 89 250, which is 35.7 steps, so the rule puts 750 g back on.
        let secondHalf = PrescriptionResolver().traced(
            .percentOfTrainingMax(percentage: 0.85),
            in: try prescriptionContext(trainingMax: trainingMax, plates: try sparsePlateGym()))
        let resolved = try #require(resolvedPrescription(secondHalf.resolution))
        #expect(resolved.target == Weight(grams: 90_000))

        let chain = firstHalf.trace.followed(by: secondHalf.trace)
        #expect(
            chain.steps == [
                .basis(.bestEstimatedOneRepMax(formula: .epley), Weight(grams: 117_333)),
                .scaled(by: 0.9, from: Weight(grams: 117_333), to: Weight(grams: 105_600)),
                .rounded(rule, from: Weight(grams: 105_600), to: Weight(grams: 105_000)),
                .basis(.trainingMax, Weight(grams: 105_000)),
                .scaled(by: 0.85, from: Weight(grams: 105_000), to: Weight(grams: 89_250)),
                .rounded(rule, from: Weight(grams: 89_250), to: Weight(grams: 90_000)),
                .loaded(
                    Weight(grams: 90_000),
                    as: .exact(
                        PlateLoading(
                            totalWeight: Weight(grams: 90_000),
                            perSide: [
                                PlateCount(plate: Weight(grams: 20_000), count: 1),
                                PlateCount(plate: Weight(grams: 15_000), count: 1),
                            ]))),
            ])

        // Two roundings rather than one, named as such: 600 g came off at the training max and
        // 750 g went back on at the slot, and a trace collapsing them cannot explain either.
        let roundings = chain.steps.filter { step in
            if case .rounded = step { return true }
            return false
        }
        #expect(roundings.count == 2)

        // Continuous across the seam — the prescription's basis is the weight the first half ended
        // at — so this is one chain rather than two lists glued together.
        #expect(expectContiguous(chain, "the joined chain") == 5)
    }

    @Test("Joining is order-sensitive, and nothing checks continuity for the caller")
    func joiningIsOrderedAndUnchecked() throws {
        let first = ResolutionTrace(steps: [.basis(.entered, Weight(grams: 1_000))])
        let second = ResolutionTrace(steps: [.basis(.topSet, Weight(grams: 2_000))])
        #expect(first.followed(by: second).steps == first.steps + second.steps)
        #expect(first.followed(by: second) != second.followed(by: first))
        #expect(first.followed(by: .empty) == first)
        #expect(ResolutionTrace.empty.followed(by: first) == first)
        // Two traces about unrelated weights join without complaint: continuity across a join is
        // the caller's to know, since only the caller resolved both halves.
        #expect(first.followed(by: second).steps.count == 2)
    }
}

// MARK: - The prescription half

@Suite("Resolution trace — the prescription half")
struct PrescriptionTraceTests {
    private let resolver = PrescriptionResolver()

    @Test("A percentage of a training max traces the basis, the factor and the rule")
    func aPercentageOfATrainingMaxTracesEveryStep() throws {
        // 100 000 × 0.83 = 83 000, which is 33.2 steps of 2.5 kg, so the rule moves it 500 g down.
        let rule = try roundingRule(Increments.twoAndAHalfKilograms, .nearest)
        let traced = resolver.traced(
            .percentOfTrainingMax(percentage: 0.83),
            in: try prescriptionContext(trainingMax: prescribedTrainingMax(100_000)))
        #expect(traced.resolution == .resolved(ResolvedPrescription(target: Weight(grams: 82_500))))
        #expect(
            traced.trace.steps == [
                .basis(.trainingMax, Weight(grams: 100_000)),
                .scaled(by: 0.83, from: Weight(grams: 100_000), to: Weight(grams: 83_000)),
                .rounded(rule, from: Weight(grams: 83_000), to: Weight(grams: 82_500)),
            ])
        // The weight the training max was taken from is not here: the fixture's source weight is
        // 999 999 g, so a basis reading it instead of the training max would be visible.
        #expect(traced.trace.steps.contains(.basis(.trainingMax, Weight(grams: 999_999))) == false)
    }

    @Test("An RPE target traces the chart lookup as its own step, and its fraction is the factor")
    func anRPETargetTracesTheChartLookup() throws {
        // 5 reps at RPE 8 is 2 in reserve, so 7 reps to failure — the standard chart's 81.1% cell.
        // 200 000 × 0.811 = 162 200, which the 2.5 kg rule takes up to 162 500.
        let rule = try roundingRule(Increments.twoAndAHalfKilograms, .nearest)
        let traced = resolver.traced(
            .rpeTarget(rpe: 8),
            in: try prescriptionContext(estimate: Weight(grams: 200_000), reps: 5))
        #expect(traced.resolution == .resolved(ResolvedPrescription(target: Weight(grams: 162_500))))
        #expect(
            traced.trace.steps == [
                .basis(.estimatedOneRepMax, Weight(grams: 200_000)),
                .effort(reps: 5, rpe: 8, repsToFailure: 7, fractionOfMax: 0.811),
                .scaled(by: 0.811, from: Weight(grams: 200_000), to: Weight(grams: 162_200)),
                .rounded(rule, from: Weight(grams: 162_200), to: Weight(grams: 162_500)),
            ])
        // The step no other case has, and one of the two that yield no weight: the fraction it found
        // is what the step after it multiplies by, so the chain's running weight is unchanged across
        // it. Required rather than subscripted, so an empty trace fails here instead of trapping.
        let chartStep = try #require(traced.trace.steps.dropFirst().first)
        #expect(chartStep.resultingWeight == nil)
    }

    @Test("A different chart moves the effort step, with no call site changing")
    func theChartIsTheAnswerInTheTraceToo() throws {
        // `repRange` 1...3 on the fixture, and 3 reps at RPE 9 is 4 from failure: the 0.5 row.
        let traced = PrescriptionResolver(rpeTable: try fixtureChart()).traced(
            .rpeTarget(rpe: 9),
            in: try prescriptionContext(
                increment: Increments.oneGram, estimate: Weight(grams: 200_000), reps: 3))
        #expect(
            traced.trace.steps == [
                .basis(.estimatedOneRepMax, Weight(grams: 200_000)),
                .effort(reps: 3, rpe: 9, repsToFailure: 4, fractionOfMax: 0.5),
                .scaled(by: 0.5, from: Weight(grams: 200_000), to: Weight(grams: 100_000)),
                .rounded(
                    try roundingRule(Increments.oneGram, .nearest),
                    from: Weight(grams: 100_000),
                    to: Weight(grams: 100_000)),
            ])
        // A one-gram rule is still a rule that ran, so the step is present and reads as a no-op.
        // That is the honest report: the alternative is hiding an operation because it changed
        // nothing this time.
        #expect(traced.trace.steps.count == 4)
    }

    @Test("The three cases carrying an entered weight trace no rounding step")
    func theEnteredWeightCasesTraceNoRoundingStep() throws {
        // 102 483 g is 17 g off the 2.5 kg grid, so a rule that ran would show in the target and in
        // the trace. Asserting the whole list is what makes the absence an assertion rather than
        // an omission.
        let entered = Weight(grams: 102_483)
        let previous = Weight(grams: 99_983)
        let context = try prescriptionContext(previous: previous)
        let expected: [(Prescription, [ResolutionStep])] = [
            (.fixedWeight(entered), [.basis(.entered, entered)]),
            (
                .previousPlusIncrement(Increments.twoAndAHalfKilograms),
                [
                    .basis(.previousPerformance, previous),
                    .incremented(
                        by: Increments.twoAndAHalfKilograms, from: previous, to: entered),
                ]
            ),
            (.bodyweight(added: entered), [.basis(.bodyweightLoad, entered)]),
        ]
        for (prescription, steps) in expected {
            let traced = resolver.traced(prescription, in: context)
            #expect(traced.resolution == .resolved(ResolvedPrescription(target: entered)))
            #expect(traced.trace.steps == steps)
        }

        // The same weight through a derived case under the same rule: 102 500 g, and a rounding step
        // to say why. Without this pairing the absences above would also be satisfied by a resolver
        // that had stopped tracing altogether.
        let derived = resolver.traced(
            .percentOfTrainingMax(percentage: 1),
            in: try prescriptionContext(trainingMax: prescribedTrainingMax(102_483)))
        #expect(
            derived.resolution == .resolved(ResolvedPrescription(target: Weight(grams: 102_500))))
        #expect(
            derived.trace.steps.last
                == .rounded(
                    try roundingRule(Increments.twoAndAHalfKilograms, .nearest),
                    from: entered,
                    to: Weight(grams: 102_500)))
    }

    @Test("Bodyweight work traces one step and never a plate step, profile or not")
    func bodyweightTracesOneStepAndNeverALoading() throws {
        let added = Weight(grams: 20_000)
        let context = try prescriptionContext(plates: try sparsePlateGym())
        #expect(
            resolver.traced(.bodyweight(added: added), in: context).trace.steps
                == [.basis(.bodyweightLoad, added)])
        // The same 20 kg as barbell work does get one — an empty bar on this gym — so the absence
        // is about the case rather than about the weight or the profile.
        #expect(
            resolver.traced(.fixedWeight(added), in: context).trace.steps == [
                .basis(.entered, added),
                .loaded(added, as: .exact(PlateLoading(totalWeight: added, perSide: []))),
            ])
    }

    @Test("Every plate step holds the resolution's own loading, for the target beside it")
    func thePlateStepHoldsTheResolutionsOwnLoading() throws {
        // The mutation this closes: a second call to the calculator, or one made before the
        // rounding rule ran. Either agrees with the answer whenever the rule happens not to move
        // the target, which is most of the time.
        let context = try fullContext()
        var loaded = 0
        for prescription in try everyPrescription() {
            let traced = resolver.traced(prescription, in: context)
            guard let resolved = resolvedPrescription(traced.resolution) else {
                #expect(traced.trace.steps.isEmpty)
                continue
            }
            if case .bodyweight = prescription {
                #expect(resolved.loading == nil)
                continue
            }
            loaded += 1
            let loading = try #require(resolved.loading)
            let plateStep = try #require(traced.trace.steps.last)
            #expect(plateStep == .loaded(resolved.target, as: loading))
            // It reports the target rather than producing a new weight, so a chain's running value
            // must not advance past it: the weight a caller reads off the end of a trace is the one
            // the resolution decided, never one the inventory suggested.
            #expect(plateStep.resultingWeight == nil)
        }
        // Anchored: six of the nine types put a weight on a bar here, `.bodyweight` resolves without
        // one, and `.amrap` and `.unrecognised` do not resolve at all.
        #expect(loaded == 6)
    }

    @Test("With no equipment profile there is no plate step, rather than an empty one")
    func noPlateStepWithoutAProfile() throws {
        let traced = resolver.traced(
            .percentOfTrainingMax(percentage: 0.83),
            in: try prescriptionContext(trainingMax: prescribedTrainingMax(100_000)))
        #expect(traced.trace.steps.count == 3)
        #expect(traced.trace.steps.last?.resultingWeight == Weight(grams: 82_500))
    }

    @Test("Every trace is a chain: each step reads the weight the last one produced")
    func everyTraceIsContiguous() throws {
        var checked = 0
        for context in [try fullContext(), try prescriptionContext()] {
            for prescription in try everyPrescription() {
                let traced = resolver.traced(prescription, in: context)
                checked += expectContiguous(
                    traced.trace, String(describing: prescription.kind))
            }
        }
        // Anchored, or a resolver emitting no steps satisfies this by having nothing to check. The
        // full context supplies 15 reading steps — 1 + 3 + 3 + 3 + 3 + 2 across the six cases that
        // reach a bar — and the empty one supplies none, every case there either refusing or
        // tracing a single basis.
        #expect(checked == 15)
    }

    @Test("resolve is traced with the trace dropped, for every prescription type")
    func resolveAgreesWithTraced() throws {
        for context in [try fullContext(), try prescriptionContext()] {
            for prescription in try everyPrescription() {
                let traced = resolver.traced(prescription, in: context)
                #expect(resolver.resolve(prescription, in: context) == traced.resolution)
                // Anchored against the two agreeing on nothing: neither side is the reason a
                // resolver that answered `.notRepresentable` for everything would give.
                #expect(traced.resolution != .unresolvable(.notRepresentable))
            }
        }
    }

    @Test("No step can carry a NaN, so a trace can be asserted by comparison")
    func noStepCarriesANaN() throws {
        // The refusals cannot promise this: `Prescription` validates nothing, so a NaN percentage is
        // handed back inside the reason and `.percentageOutOfRange(.nan)` does not equal itself. A
        // trace can, because a factor is guarded before it is applied and a chart fraction is
        // validated when the chart is built — so the step lists above are comparable at all.
        let context = try prescriptionContext(
            trainingMax: prescribedTrainingMax(100_000), estimate: Weight(grams: 200_000), reps: 5)
        let again = try prescriptionContext(
            trainingMax: prescribedTrainingMax(100_000), estimate: Weight(grams: 200_000), reps: 5)

        for percentage in [Double.nan, .infinity, -.infinity, 0, -0.5] {
            let traced = resolver.traced(.percentOfTrainingMax(percentage: percentage), in: context)
            #expect(traced.trace.steps == [.basis(.trainingMax, Weight(grams: 100_000))])
        }
        #expect(
            resolver.traced(.rpeTarget(rpe: .nan), in: context).trace.steps
                == [.basis(.estimatedOneRepMax, Weight(grams: 200_000))])

        // Every trace equals one built separately from an equal context, which a NaN anywhere in a
        // payload would break — and which is also the determinism criterion at trace level.
        for prescription in try everyPrescription() {
            #expect(
                resolver.traced(prescription, in: context).trace
                    == resolver.traced(prescription, in: again).trace)
        }
    }
}

// MARK: - The training max half

@Suite("Resolution trace — the training max half")
struct TrainingMaxTraceTests {
    private let resolver = TrainingMaxResolver(.epley)

    @Test("A derived training max traces the source, the percentage and the rule")
    func aDerivedTrainingMaxTracesEveryStep() throws {
        // A 2-rep set holds the 1RM at the weight lifted, so the source is 110 000 g rather than an
        // estimate. 110 000 × 0.9 = 99 000, which is 39.6 steps of 2.5 kg and rounds up to 100 000.
        let rule = try roundingRule(Increments.twoAndAHalfKilograms, .nearest)
        let traced = resolver.traced(
            try tracedConfiguration(.percentOfRepMax(reps: 1)), from: try tracedLog())
        #expect(
            traced.resolution
                == .resolved(
                    TrainingMax(weight: Weight(grams: 100_000), sourceWeight: Weight(grams: 110_000))))
        #expect(
            traced.trace.steps == [
                .basis(.repMax(reps: 1), Weight(grams: 110_000)),
                .scaled(by: 0.9, from: Weight(grams: 110_000), to: Weight(grams: 99_000)),
                .rounded(rule, from: Weight(grams: 99_000), to: Weight(grams: 100_000)),
            ])
        // A rep max is a weight somebody lifted, so no formula is named for it — unlike the e1RM
        // source, whose whole number depends on which formula was chosen.
        #expect(
            traced.trace.steps.contains(
                .basis(.bestEstimatedOneRepMax(formula: .epley), Weight(grams: 110_000))) == false)
        // The N is carried rather than assumed: a 2-rep set holds the 2RM at the same weight, so the
        // arithmetic is identical here and only the basis differs. Without a second N a hardcoded
        // `reps: 1` passes everything above.
        #expect(
            resolver.traced(try tracedConfiguration(.percentOfRepMax(reps: 2)), from: try tracedLog())
                .trace.steps.first == .basis(.repMax(reps: 2), Weight(grams: 110_000)))
        #expect(expectContiguous(traced.trace, "a derived training max") == 2)
    }

    @Test("A manual training max traces one step, because one thing happened")
    func aManualTrainingMaxTracesOneStep() throws {
        // 102 483 g under a 0.9 percentage and a 2.5 kg rule. Both are configured and neither runs:
        // a manual training max is the number entered, and `FR-1.5.1.8` forbids showing another.
        let entered = Weight(grams: 102_483)
        let traced = resolver.traced(try tracedConfiguration(.manual(entered)), from: [])
        #expect(
            traced.resolution == .resolved(TrainingMax(weight: entered, sourceWeight: entered)))
        #expect(traced.trace.steps == [.basis(.entered, entered)])

        // The same number as a derived source shows what was bypassed: 92 235 g scaled, 92 500 g
        // rounded, two steps that the manual trace does not have.
        let derived = resolver.traced(
            try tracedConfiguration(.percentOfRepMax(reps: 1)),
            from: [try workingSet(entered, reps: 1)])
        #expect(derived.trace.steps.count == 3)
        #expect(
            derived.resolution
                == .resolved(TrainingMax(weight: Weight(grams: 92_500), sourceWeight: entered)))
    }

    @Test("The basis names the formula the estimate came from")
    func theBasisNamesTheFormulaBehindTheEstimate() throws {
        // The one thing a caller cannot recover from the configuration: which formula produced the
        // source. Two resolvers over the same log give two different numbers, and the trace says
        // which is which rather than leaving a bare weight to be guessed at.
        let log = try tracedLog()
        let configuration = try tracedConfiguration(.percentOfE1RM)
        #expect(
            TrainingMaxResolver(.epley).traced(configuration, from: log).trace.steps.first
                == .basis(.bestEstimatedOneRepMax(formula: .epley), Weight(grams: 117_333)))
        #expect(
            TrainingMaxResolver(.brzycki).traced(configuration, from: log).trace.steps.first
                == .basis(.bestEstimatedOneRepMax(formula: .brzycki), Weight(grams: 113_143)))
    }

    @Test("resolve is traced with the trace dropped, for every source")
    func resolveAgreesWithTraced() throws {
        let log = try tracedLog()
        let sources: [TrainingMaxSource] = [
            .manual(Weight(grams: 102_483)),
            .percentOfE1RM,
            .percentOfRepMax(reps: 1),
            .percentOfRepMax(reps: 47),
        ]
        for source in sources {
            let configuration = try tracedConfiguration(source)
            let traced = resolver.traced(configuration, from: log)
            #expect(resolver.resolve(configuration, from: log) == traced.resolution)
            // Anchored: three of the four are real answers rather than all four refusing alike.
            #expect(traced.resolution != .unresolvable(.notRepresentable))
        }
        // And the empty log, where two of the three sources have nothing to read.
        for source in sources {
            let configuration = try tracedConfiguration(source)
            #expect(
                resolver.resolve(configuration, from: [])
                    == resolver.traced(configuration, from: []).resolution)
        }
    }
}
