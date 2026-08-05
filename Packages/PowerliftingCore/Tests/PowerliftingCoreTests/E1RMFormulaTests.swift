import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## What is being asserted against what (`G-6.2`, `DOD-0.1`)
//
// "Published reference values" is doing real work in that requirement, so this file is explicit
// about which layer each assertion belongs to. There are three, and only the first is a citation.
//
// **1. The published equations.** Each formula's primary source is cited on its type, and the
// algebraic identities below are read straight off the published form — Brzycki's percentage table
// falling by exactly 1/36 of the 1RM per rep, Epley at ten reps being exactly 4/3, O'Conner at ten
// being exactly 5/4, Lombardi returning the lifted weight unchanged at one rep. These are checkable
// by hand against the citation, which is what makes them reference tests rather than regression
// tests. The forms used are the ones collated by LeSuer, McCormick, Mayhew, Wasserstein & Arnold
// (1997), "The accuracy of prediction equations for estimating 1-RM performance in the bench press,
// squat, and deadlift", Journal of Strength and Conditioning Research 11(4): 211–213.
//
// **2. The gram tables.** `ReferenceTable` below was produced by evaluating those same published
// equations with an independent implementation — the system C maths library, in a throwaway harness
// recorded in T-0.14's notes — and *not* by running the code under test. That makes it an
// independent arithmetic check rather than a snapshot of whatever was written first, which is the
// failure mode T-0.14's "done when" names. It is honestly a cross-implementation check, not a
// literature citation, and is labelled as such.
//
// **3. Contract behaviour** — ranges, rounding, overflow, identity. Not reference values at all.
//
// Every expected value is in **grams**. Reference values that arrive from the literature in
// kilograms or pounds are converted through `Weight`'s own initialisers inside the test, with the
// source unit named beside them; an expectation written as `102.5` would be a floating-point weight
// wearing a disguise (`G-1.1`).

/// One row of a reference table: at `reps` reps, what each of the five published equations predicts
/// for the table's load, rounded to the nearest gram.
struct ReferenceRow: Sendable {
    let reps: Int
    let epley: Int
    let brzycki: Int
    let lombardi: Int
    let oConner: Int
    let wathan: Int
}

/// Predictions for a 100 kg lift. 100 000 g exactly, so each multiplier is readable straight off
/// its expected value — 133 333 g is 4/3.
let referenceAtOneHundredKilograms: [ReferenceRow] = [
    ReferenceRow(reps: 1, epley: 103_333, brzycki: 100_000, lombardi: 100_000, oConner: 102_500, wathan: 101_304),
    ReferenceRow(reps: 2, epley: 106_667, brzycki: 102_857, lombardi: 107_177, oConner: 105_000, wathan: 105_146),
    ReferenceRow(reps: 3, epley: 110_000, brzycki: 105_882, lombardi: 111_612, oConner: 107_500, wathan: 108_980),
    ReferenceRow(reps: 4, epley: 113_333, brzycki: 109_091, lombardi: 114_870, oConner: 110_000, wathan: 112_795),
    ReferenceRow(reps: 5, epley: 116_667, brzycki: 112_500, lombardi: 117_462, oConner: 112_500, wathan: 116_583),
    ReferenceRow(reps: 6, epley: 120_000, brzycki: 116_129, lombardi: 119_623, oConner: 115_000, wathan: 120_331),
    ReferenceRow(reps: 7, epley: 123_333, brzycki: 120_000, lombardi: 121_481, oConner: 117_500, wathan: 124_030),
    ReferenceRow(reps: 8, epley: 126_667, brzycki: 124_138, lombardi: 123_114, oConner: 120_000, wathan: 127_671),
    ReferenceRow(reps: 9, epley: 130_000, brzycki: 128_571, lombardi: 124_573, oConner: 122_500, wathan: 131_246),
    ReferenceRow(reps: 10, epley: 133_333, brzycki: 133_333, lombardi: 125_893, oConner: 125_000, wathan: 134_747),
]

/// Predictions for a 140 kg lift — an unremarkable working weight, picked so that the second table
/// shares none of the first's arithmetic conveniences. Nothing can pass by being right about one.
let referenceAtOneHundredFortyKilograms: [ReferenceRow] = [
    ReferenceRow(reps: 1, epley: 144_667, brzycki: 140_000, lombardi: 140_000, oConner: 143_500, wathan: 141_826),
    ReferenceRow(reps: 2, epley: 149_333, brzycki: 144_000, lombardi: 150_048, oConner: 147_000, wathan: 147_204),
    ReferenceRow(reps: 3, epley: 154_000, brzycki: 148_235, lombardi: 156_257, oConner: 150_500, wathan: 152_572),
    ReferenceRow(reps: 4, epley: 158_667, brzycki: 152_727, lombardi: 160_818, oConner: 154_000, wathan: 157_914),
    ReferenceRow(reps: 5, epley: 163_333, brzycki: 157_500, lombardi: 164_447, oConner: 157_500, wathan: 163_216),
    ReferenceRow(reps: 6, epley: 168_000, brzycki: 162_581, lombardi: 167_472, oConner: 161_000, wathan: 168_463),
    ReferenceRow(reps: 7, epley: 172_667, brzycki: 168_000, lombardi: 170_074, oConner: 164_500, wathan: 173_642),
    ReferenceRow(reps: 8, epley: 177_333, brzycki: 173_793, lombardi: 172_360, oConner: 168_000, wathan: 178_740),
    ReferenceRow(reps: 9, epley: 182_000, brzycki: 180_000, lombardi: 174_402, oConner: 171_500, wathan: 183_745),
    ReferenceRow(reps: 10, epley: 186_667, brzycki: 186_667, lombardi: 176_250, oConner: 175_000, wathan: 188_645),
]

/// All five closed-form formulas, for the tests that must hold of every one of them.
let allFormulas: [any RepOnlyE1RMFormula] = [Epley(), Brzycki(), Lombardi(), OConner(), Wathan()]

/// Builds a working set, failing the test rather than force unwrapping.
func workingSet(_ weight: Weight, reps: Int) throws -> SetRecord {
    try #require(SetRecord(weight: weight, reps: reps, isWarmup: false, isCompleted: true))
}

@Suite("E1RM formulas — reference values")
struct E1RMReferenceValueTests {
    /// Checks one table row against all five formulas for a lift of `base` grams.
    private func check(_ row: ReferenceRow, base: Int) {
        let weight = Weight(grams: base)
        #expect(Epley().estimate(weight: weight, reps: row.reps) == Weight(grams: row.epley))
        #expect(Brzycki().estimate(weight: weight, reps: row.reps) == Weight(grams: row.brzycki))
        #expect(Lombardi().estimate(weight: weight, reps: row.reps) == Weight(grams: row.lombardi))
        #expect(OConner().estimate(weight: weight, reps: row.reps) == Weight(grams: row.oConner))
        #expect(Wathan().estimate(weight: weight, reps: row.reps) == Weight(grams: row.wathan))
    }

    @Test("A 100 kg lift matches the reference table", arguments: referenceAtOneHundredKilograms)
    func matchesAtOneHundredKilograms(row: ReferenceRow) {
        check(row, base: 100_000)
    }

    @Test("A 140 kg lift matches the reference table", arguments: referenceAtOneHundredFortyKilograms)
    func matchesAtOneHundredFortyKilograms(row: ReferenceRow) {
        check(row, base: 140_000)
    }

    @Test("Calling through `any E1RMFormula` gives the same answer as calling concretely")
    func existentialEntryPointAgrees() throws {
        // The call path T-0.16 actually uses: `E1RMCalculator` holds a user-selected formula, which
        // is a runtime choice, so it holds an existential. Worth pinning rather than assuming,
        // because the witness arrangement is unusual — `estimate(for:)` is a requirement of
        // `E1RMFormula`, but every conformance here satisfies it from an extension on
        // `RepOnlyE1RMFormula`, a *refinement* of that protocol. Nothing else in this file exercises
        // the existential, so a dispatch regression would otherwise surface in T-0.16 instead.
        let erased: [any E1RMFormula] = [Epley(), Brzycki(), Lombardi(), OConner(), Wathan()]
        let set = try workingSet(Weight(grams: 100_000), reps: 5)
        #expect(erased.count == allFormulas.count)
        for (boxed, concrete) in zip(erased, allFormulas) {
            #expect(boxed.id == concrete.id)
            #expect(boxed.validRepRange == concrete.validRepRange)
            #expect(boxed.estimate(for: set) == concrete.estimate(weight: set.weight, reps: set.reps))
        }
        // And the range guard survives erasure — it lives in the same extension.
        let outOfRange = try workingSet(Weight(grams: 100_000), reps: 11)
        for formula in erased {
            #expect(formula.estimate(for: outOfRange) == nil)
        }
    }

    @Test("Taking a SetRecord gives the same answer as taking a weight and a rep count")
    func setRecordEntryPointAgrees() throws {
        for grams in [100_000, 140_000, 102_483, -20_000] {
            for reps in E1RMFormulaID.tabulatedRepRange {
                let set = try workingSet(Weight(grams: grams), reps: reps)
                for formula in allFormulas {
                    #expect(formula.estimate(for: set) == formula.estimate(weight: set.weight, reps: set.reps))
                }
            }
        }
    }

    @Test("Epley's worked example in pounds: 225 lb for 5 reps predicts 262.5 lb")
    func epleyWorkedExampleInPounds() throws {
        // The reference is in pounds, so the conversion happens here and the assertion is in grams
        // — 225 lb is 102 058 g, and 5/6 of the way is exactly the seven-sixths Epley calls for.
        let lifted = try #require(Weight(pounds: 225, rounding: .nearest))
        let predicted = try #require(Weight(pounds: 262.5, rounding: .nearest))
        #expect(lifted == Weight(grams: 102_058))
        #expect(Epley().estimate(weight: lifted, reps: 5) == predicted)
    }

    @Test("Brzycki's published percentage table falls by exactly one thirty-sixth per rep")
    func brzyckiPercentageTableIsLinear() {
        // Read straight off the published equation: %1RM = (37 − reps) / 36. That linearity is
        // what the 1993 table shows — 100%, 97.2%, 94.4% … 75% at ten reps — and it is the property
        // that most distinguishes Brzycki from the other four.
        let brzycki = Brzycki()
        for reps in E1RMFormulaID.tabulatedRepRange {
            let percentOfMax = 100 / brzycki.multiplier(forReps: reps)
            let expected = Double(37 - reps) / 36 * 100
            #expect(relativeError(percentOfMax, expected) <= tolerance)
        }
        #expect(relativeError(100 / brzycki.multiplier(forReps: 1), 100) <= tolerance)
        #expect(relativeError(100 / brzycki.multiplier(forReps: 10), 75) <= tolerance)
    }

    @Test("The exact rational multipliers the published equations call for")
    func exactRationalMultipliers() {
        // Where a published equation lands on a rational number, assert the rational — it can be
        // checked against the citation by hand, which a decimal cannot.
        #expect(Epley().multiplier(forReps: 10) == 4.0 / 3.0)
        #expect(Epley().multiplier(forReps: 30) == 2.0)
        #expect(Brzycki().multiplier(forReps: 1) == 1.0)
        #expect(Brzycki().multiplier(forReps: 5) == 9.0 / 8.0)
        #expect(Brzycki().multiplier(forReps: 10) == 4.0 / 3.0)
        #expect(OConner().multiplier(forReps: 10) == 1.25)
        #expect(OConner().multiplier(forReps: 40) == 2.0)
        #expect(Lombardi().multiplier(forReps: 1) == 1.0)
    }

    @Test("Epley and Brzycki cross at exactly ten reps and nowhere else in range")
    func epleyAndBrzyckiCrossAtTenReps() {
        // Two independently published equations agreeing at exactly one point is a cross-check
        // neither source can provide alone: both give 4/3 at ten reps.
        for reps in E1RMFormulaID.tabulatedRepRange {
            let same = Epley().multiplier(forReps: reps) == Brzycki().multiplier(forReps: reps)
            #expect(same == (reps == 10))
        }
    }
}

@Suite("E1RM formulas — behaviour at one rep")
struct E1RMSingleRepTests {
    // A "done when" of T-0.14, and the formulas genuinely disagree. That is a property of the
    // published equations, not a defect to smooth over, so it is documented and tested per formula
    // rather than resolved by a house rule.

    @Test("Brzycki and Lombardi return the lifted weight exactly")
    func brzyckiAndLombardiAreExactAtOneRep() {
        // Both are anchored at 100% for a single rep — Brzycki as 36/36, Lombardi as 1^0.10 — and
        // both are exact rather than within a gram, which the tests below would not distinguish if
        // they used a tolerance.
        for grams in [1, 2_500, 100_000, 102_483, 250_000, -20_000] {
            let weight = Weight(grams: grams)
            #expect(Brzycki().estimate(weight: weight, reps: 1) == weight)
            #expect(Lombardi().estimate(weight: weight, reps: 1) == weight)
        }
    }

    @Test("Epley, O'Conner and Wathan return more than the lifted weight")
    func theOtherThreeOverpredictAtOneRep() {
        // Not a defect: Epley and O'Conner are straight lines fitted to multi-rep work and do not
        // pass through the single-rep point, and Wathan's exponential is asymptotic so it never
        // reaches the anchor. 1.0333, 1.025 and 1.0130 respectively.
        let weight = Weight(grams: 100_000)
        #expect(Epley().estimate(weight: weight, reps: 1) == Weight(grams: 103_333))
        #expect(OConner().estimate(weight: weight, reps: 1) == Weight(grams: 102_500))
        #expect(Wathan().estimate(weight: weight, reps: 1) == Weight(grams: 101_304))
        #expect(Epley().multiplier(forReps: 1) > 1)
        #expect(OConner().multiplier(forReps: 1) > 1)
        #expect(Wathan().multiplier(forReps: 1) > 1)
    }

    @Test("Every formula predicts at least the weight lifted, at every rep count in range")
    func noFormulaPredictsLessThanWasLifted() throws {
        let weight = Weight(grams: 100_000)
        for formula in allFormulas {
            for reps in E1RMFormulaID.tabulatedRepRange {
                let estimate = try #require(formula.estimate(weight: weight, reps: reps))
                #expect(estimate >= weight)
            }
        }
    }

    @Test("Every formula increases with reps")
    func everyFormulaIsMonotonic() {
        for formula in allFormulas {
            for reps in 1..<10 {
                #expect(formula.multiplier(forReps: reps) < formula.multiplier(forReps: reps + 1))
            }
        }
    }
}

@Suite("E1RM formulas — the valid rep range")
struct E1RMRepRangeTests {
    @Test("Every formula declares the same range, 1 through 10")
    func everyFormulaDeclaresTheTabulatedRange() {
        for formula in allFormulas {
            #expect(formula.validRepRange == 1...10)
            #expect(formula.validRepRange == E1RMFormulaID.tabulatedRepRange)
        }
    }

    @Test("The five agree at ten reps and diverge past it, which is why the range ends there")
    func formulasDivergePastTheTabulatedRange() throws {
        // The upper bound of `tabulatedRepRange` is a decision, not a citation, and this is the
        // evidence for it. Measured multipliers, for a lift of any size:
        //
        // | reps | Epley | Brzycki | Lombardi | O'Conner | Wathan | spread |
        // |---|---|---|---|---|---|---|
        // |  10 | 1.333 | 1.333 | 1.259 | 1.250 | 1.347 | 0.097 |
        // |  15 | 1.500 | 1.636 | 1.311 | 1.375 | 1.509 | 0.325 |
        // |  20 | 1.667 | 2.118 | 1.349 | 1.500 | 1.645 | 0.769 |
        // |  30 | 2.000 | 5.143 | 1.405 | 1.750 | 1.836 | 3.738 |
        //
        // Five equations that agree to within 10% and then diverge to 370% are not five
        // measurements of the same quantity past the point they part company. Ten reps is also
        // where each was published as a percentage table.
        func spread(atReps reps: Int) throws -> Double {
            let multipliers = allFormulas.map { $0.multiplier(forReps: reps) }
            return try #require(multipliers.max()) - #require(multipliers.min())
        }
        #expect(try spread(atReps: 10) < 0.10)
        #expect(try spread(atReps: 15) > 0.30)
        #expect(try spread(atReps: 20) > 0.75)
        #expect(try spread(atReps: 30) > 3.50)
    }

    @Test("Both boundaries of the range produce an estimate")
    func boundariesAreInclusive() throws {
        let weight = Weight(grams: 100_000)
        for formula in allFormulas {
            #expect(try #require(formula.estimate(weight: weight, reps: 1)) > .zero)
            #expect(try #require(formula.estimate(weight: weight, reps: 10)) > .zero)
        }
    }

    @Test("One step outside either boundary returns nil", arguments: [0, 11])
    func outsideTheRangeReturnsNil(reps: Int) {
        // `TR-0.2.5` requires the calculator to return nil for reps outside a formula's range;
        // the formulas are where that range is known, so the refusal starts here.
        let weight = Weight(grams: 100_000)
        for formula in allFormulas {
            #expect(formula.estimate(weight: weight, reps: reps) == nil)
        }
    }

    @Test("Zero reps returns nil, which is the case a failed set actually produces")
    func zeroRepsReturnsNil() throws {
        // `SetRecord` accepts zero reps on purpose (`FR-1.2.5`), so this arrives through the front
        // door rather than only from a hand-built call. Lombardi is why the lower bound is not
        // simply left open: `0^0.10` is zero, so an unguarded estimate would be "no weight at all".
        let failedSet = try #require(
            SetRecord(weight: Weight(grams: 100_000), reps: 0, isWarmup: false, isCompleted: false))
        for formula in allFormulas {
            #expect(formula.estimate(for: failedSet) == nil)
        }
        #expect(Lombardi().multiplier(forReps: 0) == 0)
    }

    @Test("Brzycki's singularity is unreachable through the guarded entry point")
    func brzyckiSingularityIsUnreachable() {
        // The equation divides by 37 − reps. The guard lives in the protocol extension rather than
        // in `Brzycki`, which is what makes reaching the division structurally impossible instead
        // of merely untested. The unguarded multiplier shows what is being avoided.
        let weight = Weight(grams: 100_000)
        #expect(Brzycki().estimate(weight: weight, reps: 37) == nil)
        #expect(Brzycki().estimate(weight: weight, reps: 38) == nil)
        #expect(Brzycki().multiplier(forReps: 37) == .infinity)
        #expect(Brzycki().multiplier(forReps: 38) < 0)
    }

    @Test("The five equations agree at ten reps and diverge past it")
    func divergencePastTheRangeJustifiesTheCap() {
        // The measurement behind `tabulatedRepRange`'s upper bound, pinned so the doc comment's
        // table is not just a claim. Five equations that agree to within 10% and then spread to
        // 370% are not five estimates of the same quantity out there.
        func spread(atReps reps: Int) -> Double {
            let multipliers = allFormulas.map { $0.multiplier(forReps: reps) }
            // `sorted_first_last` is on, so max/min rather than sorted().first/last.
            return (multipliers.max() ?? 0) - (multipliers.min() ?? 0)
        }
        #expect(spread(atReps: 10) < 0.10)
        #expect(spread(atReps: 15) > 0.30)
        #expect(spread(atReps: 20) > 0.75)
        #expect(spread(atReps: 30) > 3.5)
    }
}

@Suite("E1RM formulas — what the formulas deliberately do not do")
struct E1RMNonResponsibilityTests {
    @Test("A warmup and an incomplete set are estimated exactly like a working set")
    func warmupAndCompletionFlagsAreIgnored() throws {
        // `TR-0.2.5` puts that filtering on `E1RMCalculator` (T-0.16). A formula that refused a
        // warmup here would make two of that calculator's three documented nil cases
        // indistinguishable from the formula simply declining, so this is asserted rather than
        // left as a comment.
        let weight = Weight(grams: 100_000)
        let working = try #require(SetRecord(weight: weight, reps: 5, isWarmup: false, isCompleted: true))
        let warmup = try #require(SetRecord(weight: weight, reps: 5, isWarmup: true, isCompleted: true))
        let failed = try #require(SetRecord(weight: weight, reps: 5, isWarmup: false, isCompleted: false))
        for formula in allFormulas {
            #expect(formula.estimate(for: warmup) == formula.estimate(for: working))
            #expect(formula.estimate(for: failed) == formula.estimate(for: working))
        }
    }

    @Test("A negative weight produces a more negative estimate, which is backwards")
    func negativeWeightIsNotCorrected() throws {
        // Assisted bodyweight work stores a negative added load (T-0.12). Every equation here is
        // linear in weight, so a multiplier above 1 makes the number *more* negative — more
        // assistance, which is easier, reported as a heavier one-rep maximum. Asserted so the
        // behaviour is visible and deliberate rather than discovered later; correcting it is an
        // obligation recorded on T-0.16 and T-0.18, because no requirement puts it here.
        let assisted = Weight(grams: -20_000)
        let estimate = try #require(Epley().estimate(weight: assisted, reps: 5))
        #expect(estimate == Weight(grams: -23_333))
        #expect(estimate < assisted)
    }

    @Test("A zero weight estimates as zero")
    func zeroWeightIsZero() {
        for formula in allFormulas {
            for reps in E1RMFormulaID.tabulatedRepRange {
                #expect(formula.estimate(weight: .zero, reps: reps) == .zero)
            }
        }
    }

    @Test("No formula rounds to a loadable increment")
    func estimatesAreNotSnappedToAnIncrement() throws {
        // An e1RM is an estimate; nobody loads it. Rounding to something a bar can hold is
        // `RoundingRule`'s job and applying it here would be a category error — so a result is
        // expected to land on an unloadable number of grams, and here it does.
        let estimate = try #require(Wathan().estimate(weight: Weight(grams: 100_000), reps: 3))
        #expect(estimate == Weight(grams: 108_980))
        #expect(estimate.grams % 2_500 != 0)
    }
}

@Suite("E1RM formulas — extreme magnitudes")
struct E1RMOverflowTests {
    @Test("A weight near Int.max overflows to nil rather than trapping")
    func overflowReturnsNil() {
        // Unreachable from any physical load, and asserted anyway: these run inside calculators
        // (T-0.16, T-0.18, T-0.19) that have no way to report a trap.
        for formula in allFormulas {
            #expect(formula.estimate(weight: Weight(grams: .max), reps: 10) == nil)
            #expect(formula.estimate(weight: Weight(grams: .min), reps: 10) == nil)
        }
    }

    @Test("A multiplier of exactly one preserves any weight a Double can hold exactly")
    func exactMultiplierPreservesTheWeight() {
        // Brzycki and Lombardi are exactly 1 at one rep. 2^53 g is the largest gram count a
        // `Double` represents without gaps — about a thousand trillion tonnes — and it comes back
        // unchanged, so the round trip through floating point costs nothing in any reachable case.
        let large = Weight(grams: 1 << 53)
        #expect(Brzycki().estimate(weight: large, reps: 1) == large)
        #expect(Lombardi().estimate(weight: large, reps: 1) == large)
    }

    @Test("Int.max overflows even at a multiplier of one, and Int.min does not")
    func theTwoBoundsAreAsymmetric() {
        // Measured, not reasoned about — the first version of this test asserted the opposite and
        // failed. `Double(Int.max)` rounds *up* to 2^63, one past the largest `Int`, so the product
        // no longer fits even when nothing is being multiplied by. `Int.min` is exactly -2^63 and
        // survives. The asymmetry belongs to `Double`, not to this module, and the guard in
        // `Weight.scaled(by:)` catches it either way.
        #expect(Brzycki().estimate(weight: Weight(grams: .max), reps: 1) == nil)
        #expect(Lombardi().estimate(weight: Weight(grams: .max), reps: 1) == nil)
        #expect(Brzycki().estimate(weight: Weight(grams: .min), reps: 1) == Weight(grams: .min))
        #expect(Epley().estimate(weight: Weight(grams: .max), reps: 1) == nil)
    }

    @Test("Scaling by a non-finite factor returns nil")
    func nonFiniteFactorReturnsNil() {
        // The other half of `Weight.scaled(by:)`'s guard. Not reachable through `estimate`, because
        // the range guard runs first — Brzycki at 37 reps is the factor that would get here.
        #expect(Weight(grams: 100_000).scaled(by: .infinity) == nil)
        #expect(Weight(grams: 100_000).scaled(by: .nan) == nil)
        #expect(Weight(grams: 100_000).scaled(by: Brzycki().multiplier(forReps: 37)) == nil)
        #expect(Weight(grams: 100_000).scaled(by: 1.5) == Weight(grams: 150_000))
    }
}

@Suite("E1RMFormulaID")
struct E1RMFormulaIDTests {
    @Test("Every formula reports its own identifier")
    func formulasReportTheirIdentifiers() {
        #expect(Epley().id == .epley)
        #expect(Brzycki().id == .brzycki)
        #expect(Lombardi().id == .lombardi)
        #expect(OConner().id == .oConner)
        #expect(Wathan().id == .wathan)
        #expect(Set(allFormulas.map(\.id)).count == allFormulas.count)
    }

    @Test("The raw spellings are pinned — changing one is a storage migration")
    func rawValuesArePinned() {
        // `TR-0.3.8` persists this string on `UserSettingsEntity`. The O'Conner case is the one
        // worth pinning: its raw value is deliberately not the Swift-derived "oConner".
        #expect(E1RMFormulaID.epley.rawValue == "epley")
        #expect(E1RMFormulaID.brzycki.rawValue == "brzycki")
        #expect(E1RMFormulaID.lombardi.rawValue == "lombardi")
        #expect(E1RMFormulaID.oConner.rawValue == "oconner")
        #expect(E1RMFormulaID.wathan.rawValue == "wathan")
        #expect(E1RMFormulaID.allCases.count == 5)
    }

    @Test("Encodes as a bare string and round-trips")
    func roundTripsThroughCodable() throws {
        for identifier in E1RMFormulaID.allCases {
            #expect(try probeEncode(identifier) == .string(identifier.rawValue))
            #expect(try probeDecode(E1RMFormulaID.self, from: .string(identifier.rawValue)) == identifier)
        }
    }

    @Test("An unrecognised name throws rather than degrading")
    func unknownIdentifierThrows() {
        // Deliberately unlike `Movement`/`Equipment`/`SetModifier`. A formula is an implementation,
        // so a name with nothing behind it cannot be computed with or meaningfully preserved — and
        // nothing upstream re-supplies it. See the type's note for the obligation this places on
        // T-0.32: an unreadable setting must fall back to a default, not cost the settings record.
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(E1RMFormulaID.self, from: .string("rpeBased"))
        }
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(E1RMFormulaID.self, from: .string(""))
        }
    }

    @Test("A non-string throws")
    func nonStringThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(E1RMFormulaID.self, from: .int(1))
        }
    }
}
