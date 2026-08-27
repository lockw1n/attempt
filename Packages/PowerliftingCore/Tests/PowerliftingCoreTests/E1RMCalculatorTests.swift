import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## What is being asserted here
//
// Contract behaviour only — no reference values. Every expected gram figure below is Epley's,
// taken from `E1RMFormulaTests`' reference table, and appears here so that a `nil` is always
// paired with a **literal** non-`nil` on an otherwise identical set. Two optionals compared to
// each other pass when both are `nil`, which is how a refusal test ends up asserting nothing.
//
// The four refusals are tested against a closed-form formula, one at a time. `RPEBased` has four
// refusals of its own, so a warmup that also records no effort is refused twice over and neither
// test would know which guard fired; it is tested separately, for pass-through.

/// A formula that ignores its own ``E1RMFormula/validRepRange`` and returns the weight unchanged,
/// so the only guard between an out-of-range set and an answer is the calculator's.
///
/// The range is a parameter because both real conformances also guard, which makes them unable to
/// tell "the calculator read *my* range" from "the calculator read the closed-form constant and I
/// refused afterwards". A formula that never refuses, at a range that is not `1...10`, can.
///
/// Reports ``E1RMFormulaID/epley`` because a fixture needs some name; it is never resolved through
/// ``E1RMFormulaID/formula`` and nothing here reads it.
struct UnguardedFormula: E1RMFormula {
    let id = E1RMFormulaID.epley
    let validRepRange: ClosedRange<Int>

    init(validRepRange: ClosedRange<Int> = 1...10) {
        self.validRepRange = validRepRange
    }

    func estimate(for set: SetRecord) -> Weight? { set.weight }
}

/// A working, completed set at 100 kg for 5 reps — the anchor case, which Epley estimates at
/// 116 667 g. Callers vary one field from it at a time.
private func anchorSet() throws -> SetRecord {
    try workingSet(Weight(grams: 100_000), reps: 5)
}

@Suite("E1RM calculator — the refusals")
struct E1RMCalculatorRefusalTests {
    private let calculator = E1RMCalculator(.epley)

    @Test("A warmup returns nil even with a rep count the formula is happy with")
    func warmupIsRefused() throws {
        let warmup = try #require(
            SetRecord(weight: Weight(grams: 100_000), reps: 5, isWarmup: true, isCompleted: true))
        #expect(calculator.estimate(for: warmup) == nil)
        // The formula itself does not filter, so the refusal above is demonstrably this type's.
        #expect(Epley().estimate(for: warmup) == Weight(grams: 116_667))
        #expect(calculator.estimate(for: try anchorSet()) == Weight(grams: 116_667))
    }

    @Test("An incomplete set returns nil")
    func incompleteIsRefused() throws {
        let failed = try #require(
            SetRecord(weight: Weight(grams: 100_000), reps: 5, isWarmup: false, isCompleted: false))
        #expect(calculator.estimate(for: failed) == nil)
        #expect(Epley().estimate(for: failed) == Weight(grams: 116_667))
        #expect(calculator.estimate(for: try anchorSet()) == Weight(grams: 116_667))
    }

    @Test("Reps outside the formula's range return nil", arguments: [0, 11])
    func outOfRangeIsRefused(reps: Int) throws {
        let set = try workingSet(Weight(grams: 100_000), reps: reps)
        #expect(calculator.estimate(for: set) == nil)
    }

    @Test("Both boundaries of the range produce an estimate")
    func rangeBoundariesAreIncluded() throws {
        #expect(calculator.estimate(for: try workingSet(Weight(grams: 100_000), reps: 1)) == Weight(grams: 103_333))
        #expect(calculator.estimate(for: try workingSet(Weight(grams: 100_000), reps: 10)) == Weight(grams: 133_333))
    }

    @Test("The rep guard is the calculator's own, not borrowed from the formula")
    func repGuardHoldsForAnUnguardedFormula() throws {
        let unguarded = E1RMCalculator(formula: UnguardedFormula())
        let outOfRange = try workingSet(Weight(grams: 100_000), reps: 11)
        #expect(UnguardedFormula().estimate(for: outOfRange) == Weight(grams: 100_000))
        #expect(unguarded.estimate(for: outOfRange) == nil)
        #expect(unguarded.estimate(for: try anchorSet()) == Weight(grams: 100_000))
    }

    @Test("The range guarded is the formula's own, in both directions, not a shared constant")
    func repRangeIsReadFromTheFormula() throws {
        let narrow = E1RMCalculator(formula: UnguardedFormula(validRepRange: 1...3))
        let wide = E1RMCalculator(formula: UnguardedFormula(validRepRange: 1...15))
        let fourReps = try workingSet(Weight(grams: 100_000), reps: 4)
        let twelveReps = try workingSet(Weight(grams: 100_000), reps: 12)
        // Four reps is inside the closed-form five's 1...10 and outside this formula's range;
        // twelve is the other way round. Reading `tabulatedRepRange` here fails both.
        #expect(narrow.estimate(for: fourReps) == nil)
        #expect(wide.estimate(for: fourReps) == Weight(grams: 100_000))
        #expect(narrow.estimate(for: twelveReps) == nil)
        #expect(wide.estimate(for: twelveReps) == Weight(grams: 100_000))
    }

    @Test("A negative weight returns nil rather than a backwards estimate")
    func negativeWeightIsRefused() throws {
        let assisted = try workingSet(Weight(grams: -20_000), reps: 5)
        #expect(calculator.estimate(for: assisted) == nil)
        // Uncorrected in the formula, on purpose: more assistance reads as a heavier maximum.
        #expect(Epley().estimate(for: assisted) == Weight(grams: -23_333))
    }

    @Test("The sign boundary sits between zero and minus one gram")
    func zeroWeightIsAllowedAndMinusOneIsNot() throws {
        #expect(calculator.estimate(for: try workingSet(Weight(grams: -1), reps: 5)) == nil)
        #expect(calculator.estimate(for: try workingSet(.zero, reps: 5)) == Weight.zero)
        #expect(calculator.estimate(for: try workingSet(Weight(grams: 1), reps: 5)) == Weight(grams: 1))
    }
}

@Suite("E1RM calculator — resolving a persisted name")
struct E1RMFormulaResolutionTests {
    @Test("Every identifier resolves to the formula that reports it")
    func resolutionIsTotalAndRoundTrips() {
        for id in E1RMFormulaID.allCases {
            #expect(id.formula.id == id)
            #expect(E1RMCalculator(id).formula.id == id)
        }
        #expect(E1RMFormulaID.allCases.count == 6)
    }

    @Test("The default formula is Epley, and a calculator built with no argument uses it")
    func defaultIsEpley() {
        #expect(E1RMFormulaID.defaultFormula == .epley)
        #expect(E1RMCalculator().formula.id == .epley)
    }

    @Test("The default formula answers for a set that records no effort, which is why it is not RPE-based")
    func defaultAnswersForAnUnratedSet() throws {
        let unrated = try anchorSet()
        #expect(unrated.rpe == nil && unrated.rir == nil)
        #expect(E1RMCalculator().estimate(for: unrated) == Weight(grams: 116_667))
        #expect(E1RMCalculator(.rpeBased).estimate(for: unrated) == nil)
    }
}

@Suite("E1RM calculator — switching the formula")
struct E1RMFormulaSwitchingTests {
    /// `FR-1.7.3` recalculates every stored e1RM when the setting changes, which is only possible
    /// because nothing is cached here (`G-1.4`): the same set answers differently under a different
    /// formula, on demand.
    @Test("The same set estimates differently under a different formula")
    func switchingFormulaChangesTheAnswer() throws {
        let set = try anchorSet()
        let epley = E1RMCalculator(.epley).estimate(for: set)
        let brzycki = E1RMCalculator(.brzycki).estimate(for: set)
        #expect(epley == Weight(grams: 116_667))
        #expect(brzycki == Weight(grams: 112_500))
        #expect(epley != brzycki)
    }

    @Test("A refusal survives the switch — no formula rescues a warmup")
    func everyFormulaRefusesAWarmup() throws {
        let warmup = try #require(
            SetRecord(
                weight: Weight(grams: 100_000), reps: 3, rpe: 8, isWarmup: true, isCompleted: true))
        let working = try ratedWorkingSet(Weight(grams: 100_000), reps: 3, rpe: 8)
        for id in E1RMFormulaID.allCases {
            // The working counterpart must answer, or the refusal above is not this type's doing —
            // `.rpeBased` in particular has four refusals of its own and could be declining for one
            // of them, leaving that iteration asserting nothing.
            #expect(E1RMCalculator(id).estimate(for: working) != nil)
            #expect(E1RMCalculator(id).estimate(for: warmup) == nil)
        }
    }
}

@Suite("E1RM calculator — with an RPE-based formula")
struct E1RMCalculatorRPETests {
    @Test("A rated working set passes straight through to the formula")
    func ratedSetAgreesWithTheFormula() throws {
        let formula = RPEBased(table: try fixtureChart())
        let set = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 9)
        #expect(E1RMCalculator(formula: formula).estimate(for: set) == Weight(grams: 133_333))
        #expect(E1RMCalculator(formula: formula).estimate(for: set) == formula.estimate(for: set))
    }

    @Test("A set recording no effort is the formula's refusal, not the calculator's")
    func unratedSetIsRefusedByTheFormula() throws {
        let calculator = E1RMCalculator(formula: RPEBased(table: try fixtureChart()))
        let unrated = try workingSet(Weight(grams: 100_000), reps: 2)
        #expect(calculator.estimate(for: unrated) == nil)
        // The calculator passed it on rather than refusing it: it accepts the set at those reps.
        let rated = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 9)
        #expect(calculator.estimate(for: rated) == Weight(grams: 133_333))
    }

    @Test("A rated warmup is refused before the chart is ever consulted")
    func warmupBeatsTheChart() throws {
        let formula = RPEBased(table: try fixtureChart())
        let warmup = try #require(
            SetRecord(
                weight: Weight(grams: 100_000), reps: 2, rpe: 9, isWarmup: true, isCompleted: true))
        #expect(E1RMCalculator(formula: formula).estimate(for: warmup) == nil)
        #expect(formula.estimate(for: warmup) == Weight(grams: 133_333))
    }

    @Test("A real chart's rep range is honoured where the closed-form constant would not be")
    func theChartsRepRangeIsHonoured() throws {
        // The fixture chart stops at 3 reps while its rows run to 4, so this is the rep-range
        // refusal rather than the off-the-end-of-the-chart one.
        let calculator = E1RMCalculator(formula: RPEBased(table: try fixtureChart()))
        let fourReps = try ratedWorkingSet(Weight(grams: 100_000), reps: 4, rpe: 10)
        #expect(calculator.estimate(for: fourReps) == nil)
        #expect(E1RMCalculator(.epley).estimate(for: fourReps) == Weight(grams: 113_333))
        let threeReps = try ratedWorkingSet(Weight(grams: 100_000), reps: 3, rpe: 9)
        #expect(calculator.estimate(for: threeReps) == Weight(grams: 200_000))
    }
}

/// `TR-0.2.5`'s refusals, reported rather than merely applied — `FR-1.13.3`'s raw material.
///
/// The point of the type is that a caller explaining a blank reads the *same* chain
/// ``E1RMCalculator/estimate(for:)`` applies, so every test here pairs the reported reason with the
/// estimate being absent for it.
@Suite("E1RM calculator — the reported reason")
struct E1RMOutcomeTests {
    private let calculator = E1RMCalculator(.epley)

    @Test("An accepted set reports its estimate rather than a reason")
    func anAcceptedSetReportsItsEstimate() throws {
        #expect(calculator.outcome(for: try anchorSet()) == .estimate(Weight(grams: 116_667)))
    }

    @Test("A warmup reports the warmup guard")
    func aWarmupReportsItself() throws {
        let warmup = try #require(
            SetRecord(weight: Weight(grams: 100_000), reps: 5, isWarmup: true, isCompleted: true))
        #expect(calculator.outcome(for: warmup) == .refused(.warmup))
        #expect(calculator.estimate(for: warmup) == nil)
    }

    @Test("An incomplete set reports the completion guard")
    func anIncompleteSetReportsItself() throws {
        let failed = try #require(
            SetRecord(weight: Weight(grams: 100_000), reps: 5, isWarmup: false, isCompleted: false))
        #expect(calculator.outcome(for: failed) == .refused(.incomplete))
    }

    @Test("Assisted work reports the sign guard")
    func assistedWorkReportsItself() throws {
        let assisted = try workingSet(Weight(grams: -20_000), reps: 5)
        #expect(calculator.outcome(for: assisted) == .refused(.assisted))
    }

    @Test("A rep count past the range reports the range guard")
    func tooManyRepsReportsItself() throws {
        let twelve = try workingSet(Weight(grams: 100_000), reps: 12)
        #expect(calculator.outcome(for: twelve) == .refused(.repsOutOfRange))
    }

    /// The distinction the type exists for: the calculator asked, and the *formula* had nothing to
    /// say. Reported as a guard it would be a refusal the calculator never made.
    @Test("A formula that declines is not reported as a guard")
    func aDecliningFormulaReportsItself() throws {
        let rpe = E1RMCalculator(formula: RPEBased(table: try fixtureChart()))
        let unrated = try workingSet(Weight(grams: 100_000), reps: 2)
        #expect(rpe.outcome(for: unrated) == .refused(.formulaDeclined))
    }

    /// **The first guard that stopped it, not the last one it would have failed.** An assisted
    /// twelve-rep set fails two, and reporting the rep range would tell the lifter to do fewer reps
    /// on work that has no estimate at any rep count.
    @Test("A set failing two guards reports the first")
    func theFirstGuardWins() throws {
        let assistedAndLong = try workingSet(Weight(grams: -20_000), reps: 12)
        #expect(calculator.outcome(for: assistedAndLong) == .refused(.assisted))
    }

    /// The ordering is what "nearest miss" means to a caller choosing between several refusals.
    @Test("The refusals are ordered by how far the set got")
    func theRefusalsAreOrderedByProgress() {
        #expect(
            E1RMRefusal.allCases.sorted()
                == [.warmup, .incomplete, .assisted, .repsOutOfRange, .formulaDeclined])
    }
}
