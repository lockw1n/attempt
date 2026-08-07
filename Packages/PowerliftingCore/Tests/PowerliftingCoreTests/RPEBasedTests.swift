import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## What is being asserted against what (`G-6.2`, `DOD-0.1`)
//
// `E1RMFormulaTests` splits into three layers — cited equations, independently computed gram
// values, and contract behaviour. This file has **only the third**, and that is a statement about
// what is finished rather than a style choice.
//
// **There is no cited chart here yet, and no default chart ships.** `RPEBased` has no
// `.standard` table and its initialiser has no default argument, so nothing in this package can
// produce an RPE estimate from percentages nobody has checked. Every table below is a *fixture*:
// its numbers are exact binary fractions chosen so interpolation and gram conversion assert
// exactly, they are labelled as fixtures, and they are not a chart anyone lifts by. A table of
// invented percentages carrying a citation is worse than no citation, so `TR-0.2.4` stays partial
// until the real chart arrives with a source attached.
//
// **What that does and does not leave untested.** Every behaviour the chart's *values* do not
// determine is tested here: which effort field wins, how a key between two rows interpolates, all
// four ways an estimate refuses, that the rep range comes from the chart, and that replacing the
// chart changes the answer with no call site changing. What is untested is whether the shipped
// percentages are the published ones — because none are shipped.
//
// The one structural claim about the real chart worth pinning early is asserted below as
// `diagonalCellsAreOneCell`: because a key is `reps + reps in reserve`, a 3-rep set at RPE 9 and a
// 4-rep set at RPE 10 must give the identical answer. That holds of any correct copy of the chart,
// so it is checkable against whichever source is chosen, and it is the property that makes a
// one-dimensional table a faithful representation of a two-dimensional grid.

/// A fixture chart. **Not a published table** — the fractions are exact binary values (15/16,
/// 7/8, 13/16, 3/4, 1/2) picked so that interpolation and the conversion to grams can be asserted
/// exactly rather than within a tolerance.
///
/// Two properties are deliberate: the last two rows are a whole rep apart, so a key falls strictly
/// between them, and `repRange` stops at 3 while the rows run to 4, so "in the rep range but off
/// the end of the chart" is reachable and distinguishable from the rep-range refusal.
func fixtureChart() throws -> RPETable {
    try #require(
        RPETable(
            entries: [
                RPETable.Entry(repsToFailure: 1, fractionOfMax: 1),
                RPETable.Entry(repsToFailure: 1.5, fractionOfMax: 0.9375),
                RPETable.Entry(repsToFailure: 2, fractionOfMax: 0.875),
                RPETable.Entry(repsToFailure: 2.5, fractionOfMax: 0.8125),
                RPETable.Entry(repsToFailure: 3, fractionOfMax: 0.75),
                RPETable.Entry(repsToFailure: 4, fractionOfMax: 0.5),
            ],
            repRange: 1...3))
}

/// A second fixture, differing from ``fixtureChart()`` in both its percentages and its rep range,
/// for the assertions that a chart is genuinely the source of the answer.
func alternativeChart() throws -> RPETable {
    try #require(
        RPETable(
            entries: [
                RPETable.Entry(repsToFailure: 1, fractionOfMax: 1),
                RPETable.Entry(repsToFailure: 2, fractionOfMax: 0.5),
                RPETable.Entry(repsToFailure: 3, fractionOfMax: 0.25),
                RPETable.Entry(repsToFailure: 4, fractionOfMax: 0.125),
                RPETable.Entry(repsToFailure: 5, fractionOfMax: 0.0625),
            ],
            repRange: 1...5))
}

/// Builds a **working** set carrying an effort rating, failing the test rather than force
/// unwrapping.
///
/// The two `G-1.8` flags are hardcoded rather than defaulted, following `workingSet`: `SetRecord`
/// refuses to default them so that every call site states them, and a helper that quietly supplies
/// them puts the same blind spot back one level up. A test needing a warmup or a failed set builds
/// the record itself, which is exactly the one place that should be visible.
func ratedWorkingSet(
    _ weight: Weight,
    reps: Int,
    rpe: Double? = nil,
    rir: Int? = nil
) throws -> SetRecord {
    try #require(
        SetRecord(
            weight: weight,
            reps: reps,
            rpe: rpe,
            rir: rir,
            isWarmup: false,
            isCompleted: true))
}

@Suite("RPETable — what counts as a chart")
struct RPETableConstructionTests {
    private func entry(_ repsToFailure: Double, _ fractionOfMax: Double) -> RPETable.Entry {
        RPETable.Entry(repsToFailure: repsToFailure, fractionOfMax: fractionOfMax)
    }

    @Test("A chart with no rows is not a chart")
    func emptyIsRejected() {
        #expect(RPETable(entries: [], repRange: 1...10) == nil)
    }

    @Test("Keys must strictly ascend")
    func keysMustStrictlyAscend() {
        // Equal keys are rejected as well as descending ones: two rows sharing a key make the value
        // there ambiguous, and leave the interpolation below dividing by a zero span.
        #expect(RPETable(entries: [entry(2, 0.9), entry(1, 0.8)], repRange: 1...10) == nil)
        #expect(RPETable(entries: [entry(1, 0.9), entry(1, 0.8)], repRange: 1...10) == nil)
        #expect(RPETable(entries: [entry(1, 0.9), entry(2, 0.8), entry(2, 0.7)], repRange: 1...10) == nil)
        #expect(RPETable(entries: [entry(1, 0.9), entry(2, 0.8)], repRange: 1...10) != nil)
    }

    @Test("A fraction outside nought-to-one is rejected")
    func fractionsAreBounded() {
        // The upper bound is the one that earns its place: a row authored as the published `83.7`
        // instead of `0.837` is the likeliest authoring error, and it would otherwise pass and make
        // every estimate a hundredfold too light without anything failing.
        #expect(RPETable(entries: [entry(1, 83.7)], repRange: 1...10) == nil)
        #expect(RPETable(entries: [entry(1, 0)], repRange: 1...10) == nil)
        #expect(RPETable(entries: [entry(1, -0.5)], repRange: 1...10) == nil)
        #expect(RPETable(entries: [entry(1, 1)], repRange: 1...10) != nil)
    }

    @Test("A rep range starting below one is rejected")
    func repRangeMustStartAtOne() {
        // The one guard a chart arriving over the wire could trip (`TR-0.5.2`). A zero-rep set is
        // legal and carries no information about a maximum, and no cell can mean "reps to failure:
        // none", so a chart claiming to cover 0 reps is malformed rather than merely unusual.
        #expect(RPETable(entries: [entry(1, 0.9)], repRange: 0...10) == nil)
        #expect(RPETable(entries: [entry(1, 0.9)], repRange: -3...10) == nil)
        #expect(RPETable(entries: [entry(1, 0.9)], repRange: 1...10) != nil)
        #expect(RPETable(entries: [entry(1, 0.9)], repRange: 5...10) != nil)
    }

    @Test("A non-finite value is rejected in either column")
    func nonFiniteIsRejected() {
        #expect(RPETable(entries: [entry(.nan, 0.9)], repRange: 1...10) == nil)
        #expect(RPETable(entries: [entry(.infinity, 0.9)], repRange: 1...10) == nil)
        #expect(RPETable(entries: [entry(1, .nan)], repRange: 1...10) == nil)
        #expect(RPETable(entries: [entry(1, .infinity)], repRange: 1...10) == nil)
    }

    @Test("A chart keeps its rows and its rep range exactly")
    func accessorsRoundTrip() throws {
        let chart = try fixtureChart()
        #expect(chart.entries.count == 6)
        #expect(chart.entries.first == entry(1, 1))
        #expect(chart.entries.last == entry(4, 0.5))
        #expect(chart.repRange == 1...3)
    }
}

@Suite("RPETable — looking a cell up")
struct RPETableLookupTests {
    @Test("Every row is returned exactly at its own key")
    func exactKeysAreExact() throws {
        let chart = try fixtureChart()
        for entry in chart.entries {
            #expect(chart.fractionOfMax(atRepsToFailure: entry.repsToFailure) == entry.fractionOfMax)
        }
    }

    @Test("A key between two rows interpolates linearly")
    func betweenRowsInterpolates() throws {
        // The fixture's last two rows are 3 → 0.75 and 4 → 0.5, a whole rep apart. Halfway is
        // 0.625 and a quarter of the way is 0.6875, both exact in binary, so this is an equality
        // rather than a tolerance.
        let chart = try fixtureChart()
        #expect(chart.fractionOfMax(atRepsToFailure: 3.5) == 0.625)
        #expect(chart.fractionOfMax(atRepsToFailure: 3.25) == 0.6875)
        #expect(chart.fractionOfMax(atRepsToFailure: 3.75) == 0.5625)
    }

    @Test("Past either end there is no answer rather than an extrapolated one")
    func outsideTheChartIsNil() throws {
        let chart = try fixtureChart()
        #expect(chart.fractionOfMax(atRepsToFailure: 0.999) == nil)
        #expect(chart.fractionOfMax(atRepsToFailure: 4.001) == nil)
        #expect(chart.fractionOfMax(atRepsToFailure: -1) == nil)
        #expect(chart.fractionOfMax(atRepsToFailure: 100) == nil)
        // The two ends are inclusive, so "outside" starts immediately past them.
        #expect(chart.fractionOfMax(atRepsToFailure: 1) == 1)
        #expect(chart.fractionOfMax(atRepsToFailure: 4) == 0.5)
    }

    @Test("A non-finite key has no answer")
    func nonFiniteKeyIsNil() throws {
        let chart = try fixtureChart()
        #expect(chart.fractionOfMax(atRepsToFailure: .nan) == nil)
        #expect(chart.fractionOfMax(atRepsToFailure: .infinity) == nil)
        #expect(chart.fractionOfMax(atRepsToFailure: -.infinity) == nil)
    }
}

@Suite("RPEBased — which effort field is read")
struct RPEBasedPrecedenceTests {
    @Test("RPE alone and RIR alone name the same cell")
    func eitherFieldAloneWorks() throws {
        // Three reps from failure either way: 2 reps at RPE 9 is 1 in reserve, and 2 reps with
        // `rir: 1` says so directly. The fixture's row at 3 gives 0.75, so 100 kg estimates as
        // 133 333 g.
        let formula = RPEBased(table: try fixtureChart())
        let byRPE = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 9)
        let byRIR = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rir: 1)
        #expect(formula.estimate(for: byRPE) == Weight(grams: 133_333))
        #expect(formula.estimate(for: byRIR) == Weight(grams: 133_333))
    }

    @Test("When both are present and contradict each other, RPE wins")
    func rpeWinsOverRir() throws {
        // `SetRecord` lets these disagree and does not reconcile them (`G-1.6`), so this formula
        // resolves rather than refuses. `rpe: 9` is 1 rep in reserve; `rir: 3` claims 3. The answer
        // is the one RPE names, and neither field is altered.
        let formula = RPEBased(table: try fixtureChart())
        let contradictory = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 9, rir: 3)
        let rpeOnly = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 9)
        let rirOnly = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rir: 3)
        #expect(formula.estimate(for: contradictory) == formula.estimate(for: rpeOnly))
        #expect(formula.estimate(for: contradictory) != formula.estimate(for: rirOnly))
        #expect(contradictory.rpe == 9)
        #expect(contradictory.rir == 3)
    }

    @Test("A set with neither field has nothing to look up")
    func neitherFieldIsNil() throws {
        let formula = RPEBased(table: try fixtureChart())
        let unrated = try ratedWorkingSet(Weight(grams: 100_000), reps: 2)
        #expect(formula.estimate(for: unrated) == nil)
        #expect(RPEBased.repsInReserve(for: unrated) == nil)
    }

    @Test("Reps in reserve is read off the RPE scale's own upper bound")
    func reserveIsDerivedFromTheScale() throws {
        // `rir = 10 - rpe`, where the 10 is `SetRecord.rpeRange.upperBound` rather than a literal —
        // one place defines the scale.
        #expect(try RPEBased.repsInReserve(for: ratedWorkingSet(Weight(grams: 1), reps: 1, rpe: 10)) == 0)
        #expect(try RPEBased.repsInReserve(for: ratedWorkingSet(Weight(grams: 1), reps: 1, rpe: 8.5)) == 1.5)
        #expect(try RPEBased.repsInReserve(for: ratedWorkingSet(Weight(grams: 1), reps: 1, rpe: 1)) == 9)
        #expect(try RPEBased.repsInReserve(for: ratedWorkingSet(Weight(grams: 1), reps: 1, rir: 4)) == 4)
    }
}

@Suite("RPEBased — the chart is the answer")
struct RPEBasedChartTests {
    @Test("A cell reached two ways is one cell")
    func diagonalCellsAreOneCell() throws {
        // The structural property that lets a two-dimensional chart be stored as one sequence: a
        // cell depends only on reps plus reps in reserve. Three reps at RPE 9 and two reps at
        // RPE 8 are both four from failure, so they are the same cell and must agree exactly.
        let formula = RPEBased(table: try fixtureChart())
        let weight = Weight(grams: 100_000)
        let threeAtNine = try ratedWorkingSet(weight, reps: 3, rpe: 9)
        let twoAtEight = try ratedWorkingSet(weight, reps: 2, rpe: 8)
        #expect(formula.estimate(for: threeAtNine) == formula.estimate(for: twoAtEight))
        #expect(formula.estimate(for: threeAtNine) == Weight(grams: 200_000))
    }

    @Test("Replacing the chart changes the answer, with no call site changing")
    func theChartIsSwappable() throws {
        // The scope's headline: `TR-0.5.2` delivers a replacement chart over the wire, so swapping
        // it must be constructing a different value and nothing else. Same set, same call, two
        // charts, two answers.
        let set = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 9)
        let formulas: [any E1RMFormula] = [
            RPEBased(table: try fixtureChart()), RPEBased(table: try alternativeChart()),
        ]
        #expect(formulas[0].estimate(for: set) == Weight(grams: 133_333))
        #expect(formulas[1].estimate(for: set) == Weight(grams: 400_000))
    }

    @Test("The valid rep range comes from the chart, not from the closed-form five")
    func repRangeComesFromTheChart() throws {
        let fixture = RPEBased(table: try fixtureChart())
        let alternative = RPEBased(table: try alternativeChart())
        #expect(fixture.validRepRange == 1...3)
        #expect(alternative.validRepRange == 1...5)
        #expect(fixture.validRepRange != E1RMFormulaID.tabulatedRepRange)
    }

    @Test("A half-point RPE lands on a row exactly; a finer one interpolates")
    func halfPointsAreExactAndFinerValuesInterpolate() throws {
        // The chart is keyed at half reps because the RPE scale is, so a half point is a lookup
        // rather than an interpolation — 2 reps at RPE 9.5 is 2.5 from failure, one of the
        // fixture's own rows, returned exactly. RPE 8.25 is 3.75 from failure, which falls between
        // rows: `SetRecord` tolerates the off-step value on purpose, so this formula has to answer
        // for it rather than assume the input landed on a key.
        let formula = RPEBased(table: try fixtureChart())
        let weight = Weight(grams: 100_000)
        let onAHalfPoint = try ratedWorkingSet(weight, reps: 2, rpe: 9.5)
        let offTheStep = try ratedWorkingSet(weight, reps: 2, rpe: 8.25)
        #expect(formula.estimate(for: onAHalfPoint) == Weight(grams: 123_077))
        #expect(formula.estimate(for: offTheStep) == Weight(grams: 177_778))
    }
}

@Suite("RPEBased — the four ways it declines")
struct RPEBasedRefusalTests {
    @Test("Reps outside the chart's rep range", arguments: [0, 4, 11])
    func repsOutsideTheRange(reps: Int) throws {
        let formula = RPEBased(table: try fixtureChart())
        let set = try ratedWorkingSet(Weight(grams: 100_000), reps: reps, rpe: 10)
        #expect(formula.estimate(for: set) == nil)
    }

    @Test("Both boundaries of the rep range do produce an estimate")
    func rangeBoundariesEstimate() throws {
        let formula = RPEBased(table: try fixtureChart())
        #expect(formula.estimate(for: try ratedWorkingSet(Weight(grams: 100_000), reps: 1, rpe: 10)) != nil)
        #expect(formula.estimate(for: try ratedWorkingSet(Weight(grams: 100_000), reps: 3, rpe: 10)) != nil)
    }

    @Test("An effort inside the rep range but off the end of the chart")
    func effortOffTheChart() throws {
        // Distinct from the rep-range refusal and worth its own test: 3 reps is inside `1...3`, but
        // at RPE 8 that is 5 reps from failure and the fixture's last row is 4. The chart declines
        // where the rep range does not.
        let formula = RPEBased(table: try fixtureChart())
        let set = try ratedWorkingSet(Weight(grams: 100_000), reps: 3, rpe: 8)
        #expect(formula.validRepRange.contains(set.reps))
        #expect(formula.estimate(for: set) == nil)
    }

    @Test("A set recording no effort at all")
    func noEffortRecorded() throws {
        let formula = RPEBased(table: try fixtureChart())
        #expect(formula.estimate(for: try ratedWorkingSet(Weight(grams: 100_000), reps: 2)) == nil)
    }

    @Test("A weight the estimate cannot fit back into")
    func overflowIsNil() throws {
        // Unreachable from a physical load, asserted anyway: this runs inside calculators (T-0.16,
        // T-0.18, T-0.19) with no way to report a trap.
        let formula = RPEBased(table: try fixtureChart())
        #expect(formula.estimate(for: try ratedWorkingSet(Weight(grams: .max), reps: 2, rpe: 9)) == nil)
        #expect(formula.estimate(for: try ratedWorkingSet(Weight(grams: .min), reps: 2, rpe: 9)) == nil)
    }
}

@Suite("RPEBased — what it deliberately does not do")
struct RPEBasedNonBehaviourTests {
    @Test("A warmup and an incomplete set are estimated exactly like a working set")
    func effortFlagsAreIgnored() throws {
        // `TR-0.2.5` puts input filtering on `E1RMCalculator` (T-0.16), not here. A formula that
        // refused a warmup would make two of that calculator's three documented `nil` cases
        // indistinguishable from this formula declining — and this one already has four refusals of
        // its own, so the confusion would be worse here than anywhere.
        let formula = RPEBased(table: try fixtureChart())
        let weight = Weight(grams: 100_000)
        let working = try ratedWorkingSet(weight, reps: 2, rpe: 9)
        let warmup = try #require(
            SetRecord(weight: weight, reps: 2, rpe: 9, isWarmup: true, isCompleted: true))
        let failed = try #require(
            SetRecord(weight: weight, reps: 2, rpe: 9, isWarmup: false, isCompleted: false))
        // Anchored non-nil first: without this the three comparisons below would all hold if every
        // estimate were `nil`, and this is the only test of the property.
        #expect(formula.estimate(for: working) == Weight(grams: 133_333))
        #expect(formula.estimate(for: warmup) == formula.estimate(for: working))
        #expect(formula.estimate(for: failed) == formula.estimate(for: working))
    }

    @Test("A negative weight produces a more negative estimate, which is backwards")
    func negativeWeightIsUncorrected() throws {
        // Assisted work stores a negative added load, and a chart multiplier is above 1, so more
        // assistance is reported as a heavier maximum. Asserted so it is visible rather than
        // latent; the closed-form five behave identically and T-0.16 or T-0.18 owns the decision.
        let formula = RPEBased(table: try fixtureChart())
        let assisted = try ratedWorkingSet(Weight(grams: -20_000), reps: 2, rpe: 9)
        let estimate = try #require(formula.estimate(for: assisted))
        #expect(estimate == Weight(grams: -26_667))
        #expect(estimate < assisted.weight)
    }

    @Test("The estimate is not snapped to a loadable increment")
    func estimatesAreNotSnappedToAnIncrement() throws {
        // Rounding to what a bar can hold is `RoundingRule`'s job and would be a category error
        // here: nobody loads an estimate. So a result is expected to land on an unloadable number
        // of grams, and here it does.
        let formula = RPEBased(table: try fixtureChart())
        let estimate = try #require(
            formula.estimate(for: try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 9)))
        #expect(estimate == Weight(grams: 133_333))
        #expect(estimate.grams % 2_500 != 0)
    }

    @Test("Calling through `any E1RMFormula` gives the same answer as calling concretely")
    func existentialEntryPointAgrees() throws {
        // The call path T-0.16 uses, and worth pinning separately from the closed-form five: those
        // satisfy `estimate(for:)` from an extension on a refinement, whereas this type declares it
        // directly, so it is a different witness arrangement reaching the same requirement.
        let concrete = RPEBased(table: try fixtureChart())
        let erased: any E1RMFormula = concrete
        let set = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 9)
        #expect(erased.id == concrete.id)
        #expect(erased.validRepRange == concrete.validRepRange)
        // Anchored, so the comparison cannot hold by both sides being `nil`.
        #expect(erased.estimate(for: set) == Weight(grams: 133_333))
        #expect(erased.estimate(for: set) == concrete.estimate(for: set))
    }

    @Test("It reports its own identifier, which no other formula claims")
    func reportsItsIdentifier() throws {
        let formula = RPEBased(table: try fixtureChart())
        #expect(formula.id == .rpeBased)
        #expect(!allFormulas.map(\.id).contains(formula.id))
    }
}
