import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## What is being asserted here
//
// Contract behaviour only. Every gram figure is either a logged load chosen by the fixture or
// Epley's, taken from `E1RMFormulaTests`' reference table. Each refusal is paired with a **literal**
// non-`nil` showing what the excluded set *would* have won, because this type is mostly a filter and
// a ranking: an assertion that a record is absent proves nothing on its own, and two optionals
// compared to each other pass when both are `nil`.
//
// `sharedLog` carries six of the contract's properties at once, which is why the excluded sets in it
// are the heaviest ones present — a leak changes an answer rather than going unnoticed.

/// One exercise's sets, oldest first — the fixture most tests below read.
///
/// | # | set | |
/// |---|---|---|
/// | 0 | 150 kg × 5, warmup | heavier than everything: a leak wins every record |
/// | 1 | 100 kg × 5 | holds the 3RM–5RM |
/// | 2 | 110 kg × 2 | holds the 1RM–2RM, and the best e1RM |
/// | 3 | 120 kg × 1, not completed | heavier still: a leak takes the 1RM |
/// | 4 | 100 kg × 5 | ties offset 1, and must lose the tie |
private func sharedLog() throws -> [SetRecord] {
    [
        try #require(
            SetRecord(weight: Weight(grams: 150_000), reps: 5, isWarmup: true, isCompleted: true)),
        try workingSet(Weight(grams: 100_000), reps: 5),
        try workingSet(Weight(grams: 110_000), reps: 2),
        try #require(
            SetRecord(weight: Weight(grams: 120_000), reps: 1, isWarmup: false, isCompleted: false)),
        try workingSet(Weight(grams: 100_000), reps: 5),
    ]
}

@Suite("Personal records — the definition")
struct PersonalRecordDefinitionTests {
    private let calculator = PersonalRecordCalculator(.epley)

    @Test("A 5-rep set holds every record from the 1RM to the 5RM, and none above it")
    func aSetCountsTowardEveryRepMaxAtOrBelowItsReps() throws {
        let log = [try workingSet(Weight(grams: 100_000), reps: 5)]
        let records = calculator.records(in: log)
        for reps in 1...5 {
            #expect(records.repMax(forReps: reps) == PersonalRecord(weight: Weight(grams: 100_000), setOffset: 0))
        }
        for reps in 6...10 {
            #expect(records.repMax(forReps: reps) == nil)
        }
        #expect(records.repMaxes.map(\.reps) == [1, 2, 3, 4, 5])
    }

    @Test("Fewer reps at a heavier load takes the low N; the lighter set keeps the high N")
    func heavierForFewerRepsWinsOnlyTheRepsItReached() throws {
        let records = calculator.records(in: try sharedLog())
        #expect(records.repMax(forReps: 1) == PersonalRecord(weight: Weight(grams: 110_000), setOffset: 2))
        #expect(records.repMax(forReps: 2) == PersonalRecord(weight: Weight(grams: 110_000), setOffset: 2))
        #expect(records.repMax(forReps: 3) == PersonalRecord(weight: Weight(grams: 100_000), setOffset: 1))
        #expect(records.repMax(forReps: 5) == PersonalRecord(weight: Weight(grams: 100_000), setOffset: 1))
        #expect(records.repMax(forReps: 6) == nil)
        #expect(records.repMaxes.map(\.reps) == [1, 2, 3, 4, 5])
    }

    @Test("A tie resolves to the earlier set, and a later heavier set still displaces")
    func tiesResolveToTheEarlierSet() throws {
        // Offsets 1 and 4 are both 100 kg × 5. The 3RM is the tie; the 1RM proves that losing a tie
        // is not the same as being ignored, since offset 2 is later than offset 1 and wins.
        let records = calculator.records(in: try sharedLog())
        #expect(records.repMax(forReps: 3)?.setOffset == 1)
        #expect(records.repMax(forReps: 1)?.setOffset == 2)
    }

    @Test("Rep counts outside 1...10 are refused rather than answered", arguments: [-1, 0, 11])
    func repMaxIsDefinedOnlyOverTheRequirementsRange(reps: Int) throws {
        let log = try sharedLog()
        #expect(calculator.repMax(forReps: reps, in: log) == nil)
        #expect(calculator.repMax(forReps: 1, in: log)?.weight == Weight(grams: 110_000))
    }

    @Test("Both entry points answer the same question")
    func recordsAgreesWithTheSingleRepMax() throws {
        let log = try sharedLog()
        let records = calculator.records(in: log)
        for reps in PersonalRecords.repRange {
            #expect(records.repMax(forReps: reps) == calculator.repMax(forReps: reps, in: log))
        }
        #expect(PersonalRecords.repRange == 1...10)
    }

    @Test("An empty log holds nothing at all")
    func anEmptyLogHasNoRecords() {
        let records = calculator.records(in: [])
        #expect(records.repMaxes.isEmpty)
        #expect(records.bestE1RM == nil)
        #expect(records.repMax(forReps: 1) == nil)
    }
}

@Suite("Personal records — the exclusions")
struct PersonalRecordExclusionTests {
    private let calculator = PersonalRecordCalculator(.epley)

    @Test("A warmup sets no record, however heavy")
    func warmupsAreExcluded() throws {
        let warmup = try #require(
            SetRecord(weight: Weight(grams: 150_000), reps: 5, isWarmup: true, isCompleted: true))
        #expect(calculator.records(in: [warmup]).repMax(forReps: 1) == nil)
        #expect(calculator.records(in: [warmup]).bestE1RM == nil)
        // The same load logged as working takes both, so the refusal above is the flag's doing.
        let working = try workingSet(Weight(grams: 150_000), reps: 5)
        #expect(calculator.records(in: [working]).repMax(forReps: 1)?.weight == Weight(grams: 150_000))
        #expect(calculator.records(in: [working]).bestE1RM?.weight == Weight(grams: 175_000))
    }

    @Test("An incomplete set sets no record, and a failed set contributes none of the reps it reached")
    func incompleteSetsAreExcluded() throws {
        let failed = try #require(
            SetRecord(weight: Weight(grams: 120_000), reps: 8, isWarmup: false, isCompleted: false))
        #expect(calculator.records(in: [failed]).repMaxes.isEmpty)
        #expect(calculator.records(in: [failed]).bestE1RM == nil)
        // `TR-0.2.8` says "completed working set", so the eight reps actually performed are worth
        // nothing — not even an 8RM. `FR-1.6.1` says only "working sets only"; see coverage gap 15.
        let completed = try workingSet(Weight(grams: 120_000), reps: 8)
        #expect(calculator.records(in: [completed]).repMax(forReps: 8)?.weight == Weight(grams: 120_000))
    }

    @Test("Neither exclusion reaches the log's real records")
    func theHeaviestSetsInTheFixtureAreTheExcludedOnes() throws {
        let log = try sharedLog()
        #expect(Epley().estimate(for: log[0]) == Weight(grams: 175_000))
        #expect(log[3].weight == Weight(grams: 120_000))
        // Both beat every answer below, so a leak in either filter changes one of them.
        let records = calculator.records(in: log)
        #expect(records.repMax(forReps: 1)?.weight == Weight(grams: 110_000))
        #expect(records.bestE1RM?.weight == Weight(grams: 117_333))
    }

    @Test("A zero-rep failure is a candidate for no N")
    func zeroRepsHoldsNothing() throws {
        let missed = try workingSet(Weight(grams: 200_000), reps: 0)
        #expect(calculator.records(in: [missed]).repMaxes.isEmpty)
        #expect(calculator.repMax(forReps: 1, in: [missed]) == nil)
    }
}

@Suite("Personal records — the estimated maximum")
struct PersonalRecordE1RMTests {
    private let calculator = PersonalRecordCalculator(.epley)

    @Test("The best estimate is not the heaviest load, and points at the set that produced it")
    func bestE1RMRanksEstimatesRatherThanLoads() throws {
        // 110 kg × 2 estimates at 117 333 and 100 kg × 5 at 116 667, so the lighter-but-longer set
        // loses the e1RM while still holding the 3RM through 5RM.
        let records = calculator.records(in: try sharedLog())
        #expect(records.bestE1RM == PersonalRecord(weight: Weight(grams: 117_333), setOffset: 2))
        #expect(records.repMax(forReps: 5)?.setOffset == 1)
    }

    @Test("An estimate tie resolves to the earlier set, and a better later estimate still displaces")
    func estimateTiesResolveToTheEarlierSet() throws {
        // 96 kg × 5 and 105 kg × 2 are both exactly 112 000 under Epley, and their *loads* differ —
        // so this pins that the ranking and its tie-break are on the estimate, not on the weight.
        // `sharedLog`'s own e1RM tie cannot show this: a third set outranks both, so the tie never
        // decides the answer there.
        let tied = [
            try workingSet(Weight(grams: 96_000), reps: 5),
            try workingSet(Weight(grams: 105_000), reps: 2),
        ]
        #expect(Epley().estimate(for: tied[1]) == Epley().estimate(for: tied[0]))
        #expect(calculator.bestE1RM(in: tied) == PersonalRecord(weight: Weight(grams: 112_000), setOffset: 0))
        // Losing a tie is not the same as being ignored: a later, strictly better estimate wins.
        let displaced = tied + [try workingSet(Weight(grams: 110_000), reps: 2)]
        #expect(calculator.bestE1RM(in: displaced) == PersonalRecord(weight: Weight(grams: 117_333), setOffset: 2))
    }

    @Test("An RPE-based formula declines most logs, and the rep maxes are unaffected")
    func anUnratedLogHasRepMaxesAndNoEstimate() throws {
        // Not a refusal of this calculator's: `RPEBased` has nothing to say about a set recording
        // neither an RPE nor an RIR, which is most sets — so `.rpeBased` yields no e1RM record at
        // all over an unrated log, while every rep max still stands.
        let unrated = try sharedLog()
        let rpe = PersonalRecordCalculator(.rpeBased)
        #expect(rpe.bestE1RM(in: unrated) == nil)
        #expect(rpe.repMax(forReps: 1, in: unrated)?.weight == Weight(grams: 110_000))
        // A rated log estimates, so the nil above is the missing effort rather than the formula.
        let rated = [try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 9)]
        #expect(rpe.bestE1RM(in: rated) != nil)
    }

    @Test("Every refusal is read through the calculator, not the bare formula")
    func estimatesGoThroughTheFilteringCalculator() throws {
        // `UnguardedFormula` answers for anything, so the only guard left in the path is
        // `E1RMCalculator`'s. Reading `e1rm.formula.estimate(for:)` here would let all three score,
        // and no arrangement of the real formulas could tell — they all guard themselves.
        let unguarded = PersonalRecordCalculator(e1rm: E1RMCalculator(formula: UnguardedFormula()))
        let load = Weight(grams: 100_000)
        let warmup = try #require(SetRecord(weight: load, reps: 5, isWarmup: true, isCompleted: true))
        let failed = try #require(SetRecord(weight: load, reps: 5, isWarmup: false, isCompleted: false))
        let assisted = try workingSet(Weight(grams: -20_000), reps: 5)
        for refused in [warmup, failed, assisted] {
            #expect(UnguardedFormula().estimate(for: refused) == refused.weight)
            #expect(unguarded.bestE1RM(in: [refused]) == nil)
        }
        #expect(unguarded.bestE1RM(in: [try workingSet(load, reps: 5)])?.weight == load)
    }

    @Test("Reps outside the formula's range cost the estimate but not the rep max")
    func repsOutsideTheFormulaRangeStillSetARepMax() throws {
        let longSet = try workingSet(Weight(grams: 100_000), reps: 11)
        let records = calculator.records(in: [longSet])
        #expect(records.bestE1RM == nil)
        #expect(records.repMax(forReps: 10)?.weight == Weight(grams: 100_000))
        #expect(records.repMaxes.count == 10)
    }

    @Test("Switching the formula changes the estimate for the same log")
    func switchingFormulaChangesTheAnswer() throws {
        // `G-1.4`: nothing is cached, so `FR-1.6.4` and `FR-1.7.3` can recalculate history from a
        // settings change. Both figures are Epley's and Brzycki's for 110 kg × 2.
        let log = try sharedLog()
        #expect(PersonalRecordCalculator(.epley).bestE1RM(in: log)?.weight == Weight(grams: 117_333))
        #expect(PersonalRecordCalculator(.brzycki).bestE1RM(in: log)?.weight == Weight(grams: 113_143))
        // The rep maxes read no formula, so they do not move.
        #expect(PersonalRecordCalculator(.brzycki).repMax(forReps: 1, in: log)?.weight == Weight(grams: 110_000))
    }

    @Test("A calculator built with no argument uses the default formula")
    func defaultFormulaIsUsed() throws {
        let log = try sharedLog()
        #expect(PersonalRecordCalculator().e1rm.formula.id == E1RMFormulaID.defaultFormula)
        #expect(PersonalRecordCalculator().bestE1RM(in: log) == PersonalRecordCalculator(.epley).bestE1RM(in: log))
    }
}

@Suite("Personal records — assisted work")
struct PersonalRecordAssistedTests {
    private let calculator = PersonalRecordCalculator(.epley)

    /// Assisted bodyweight work stores a negative *added* load, so less assistance is the heavier
    /// lift and `Comparable` already ranks it that way. `E1RMCalculator` refuses a negative weight
    /// because every equation is linear in weight and reports more assistance as a heavier maximum
    /// (requirements gap 13) — so this is the one input with rep maxes and no estimate at all.
    @Test("Assisted sets have N-rep maxes and no estimated maximum")
    func assistedWorkRanksButDoesNotEstimate() throws {
        let log = [
            try workingSet(Weight(grams: -20_000), reps: 5),
            try workingSet(Weight(grams: -10_000), reps: 5),
        ]
        let records = calculator.records(in: log)
        #expect(records.repMax(forReps: 5) == PersonalRecord(weight: Weight(grams: -10_000), setOffset: 1))
        #expect(records.bestE1RM == nil)
        // Not a refusal of the whole log: an unassisted set in the same log still estimates.
        let mixed = log + [try workingSet(Weight(grams: 5_000), reps: 5)]
        #expect(calculator.records(in: mixed).bestE1RM?.weight == Weight(grams: 5_833))
    }

    @Test("Zero is a real load, and sits between assisted and loaded work")
    func zeroIsRankedNotTreatedAsAbsent() throws {
        let log = [
            try workingSet(Weight(grams: -10_000), reps: 3),
            try workingSet(.zero, reps: 3),
        ]
        #expect(calculator.repMax(forReps: 3, in: log) == PersonalRecord(weight: .zero, setOffset: 1))
        // An absent record and a record of zero are different answers, which is why an unreached
        // rep count is omitted from `repMaxes` rather than stored at zero.
        #expect(calculator.repMax(forReps: 4, in: log) == nil)
    }
}
