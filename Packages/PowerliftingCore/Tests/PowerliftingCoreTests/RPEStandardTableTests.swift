import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## These are pinning tests, not reference tests (`G-6.2`)
//
// `RPETable.standard` was **transcribed from the RPE/RIR chart in wide circulation and has not
// been verified against a primary publication** — the caveat is on the type, and it applies to
// every assertion below. Nothing here should be read as "the published values are correct". What
// these tests do establish is that the shipped table is *internally* what a chart has to be, and
// that the code reads it the way the chart is meant to be read.
//
// **So the expected values are written in a different shape and a different unit from the source.**
// `RPETable.standard` stores one ascending sequence of fractions keyed by reps-plus-reserve;
// `standardChartAsPublished` below is the familiar two-dimensional grid of percentages, RPE by
// reps. Restating the same 26 numbers in the same shape would assert nothing, whereas expanding
// them to 80 cells across two axes genuinely checks the collapse, the key arithmetic, the rep
// range and the percent-to-fraction convention. A transcription error that reached only one of the
// two shapes fails here.
//
// **What stays untested is whether the numbers are the published ones.** That is not a gap this
// file can close, and `G-6.2` is recorded as outstanding rather than met.

/// One row of the chart as it is usually printed: an RPE, and the %1RM at 1 through 10 reps.
struct StandardChartRow: Sendable {
    let rpe: Double
    let percentages: [Double]
}

/// The chart in its published two-dimensional form, in **percent**. See this file's header for why
/// it is written out this way rather than reused from the source.
let standardChartAsPublished: [StandardChartRow] = [
    StandardChartRow(rpe: 10, percentages: [100.0, 95.5, 92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9]),
    StandardChartRow(rpe: 9.5, percentages: [97.8, 93.9, 90.7, 87.8, 85.0, 82.4, 79.9, 77.4, 75.1, 72.3]),
    StandardChartRow(rpe: 9, percentages: [95.5, 92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7]),
    StandardChartRow(rpe: 8.5, percentages: [93.9, 90.7, 87.8, 85.0, 82.4, 79.9, 77.4, 75.1, 72.3, 69.4]),
    StandardChartRow(rpe: 8, percentages: [92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7, 68.0]),
    StandardChartRow(rpe: 7.5, percentages: [90.7, 87.8, 85.0, 82.4, 79.9, 77.4, 75.1, 72.3, 69.4, 66.7]),
    StandardChartRow(rpe: 7, percentages: [89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7, 68.0, 65.3]),
    StandardChartRow(rpe: 6.5, percentages: [87.8, 85.0, 82.4, 79.9, 77.4, 75.1, 72.3, 69.4, 66.7, 63.8]),
]

@Suite("RPETable.standard — the shipped chart")
struct StandardChartTests {
    @Test("Every published cell is reproduced", arguments: standardChartAsPublished)
    func everyPublishedCellIsReproduced(row: StandardChartRow) {
        // 80 cells against 26 stored rows. The tolerance is float noise from the ÷100 only — the
        // two sides are the same decimal written two ways, so anything looser would hide a digit.
        #expect(row.percentages.count == 10)
        for (index, percentage) in row.percentages.enumerated() {
            let reps = index + 1
            let key = Double(reps) + (SetRecord.rpeRange.upperBound - row.rpe)
            let actual = RPETable.standard.fractionOfMax(atRepsToFailure: key)
            #expect(actual != nil, "no cell at \(reps) reps, RPE \(row.rpe)")
            if let actual {
                #expect(
                    (actual - percentage / 100).magnitude < 1e-12,
                    "\(reps) reps at RPE \(row.rpe): expected \(percentage)%, got \(actual * 100)%")
            }
        }
    }

    @Test("The published grid is constant down its diagonals")
    func thePublishedGridIsConstantDownItsDiagonals() {
        // The property that lets a two-dimensional chart be stored as one sequence: one more rep at
        // one point higher RPE is the same distance from failure, so it is the same cell. Rows here
        // descend by half a point, so "+1 rep, +1 RPE" is two rows up and one column right.
        //
        // **Asserted against the grid literal, deliberately, and not through `estimate`.** The
        // source stores the sequence and computes `reps + (10 - rpe)`, so going through the formula
        // would make this identity structurally true whatever the numbers were — a test that cannot
        // fail. Against the grid it has teeth: a single mistyped cell in the 80 written out above
        // breaks it. Paired with `everyPublishedCellIsReproduced`, which checks the grid against the
        // sequence, that pins the transcription from both directions.
        for row in 2..<standardChartAsPublished.count {
            for reps in 1...9 {
                let here = standardChartAsPublished[row].percentages[reps - 1]
                let diagonal = standardChartAsPublished[row - 2].percentages[reps]
                #expect(
                    here == diagonal,
                    """
                    \(reps) reps at RPE \(standardChartAsPublished[row].rpe) is \(here)%, but \
                    \(reps + 1) reps at RPE \(standardChartAsPublished[row - 2].rpe) is \(diagonal)%
                    """)
            }
        }
    }

    @Test("The same cell reached two ways gives the same estimate")
    func diagonalCellsAgreeThroughTheFormula() throws {
        // The consequence of the above, through the public entry point. Structurally guaranteed by
        // how the table is keyed, so it is a contract check rather than evidence about the chart —
        // kept because it is the property a caller actually relies on, and because it would catch a
        // future change to how the key is computed.
        let formula = RPEBased()
        let weight = Weight(grams: 100_000)
        for reps in 1...9 {
            for halfPoints in 0...5 {
                let rpe = 6.5 + Double(halfPoints) / 2
                let here = try ratedWorkingSet(weight, reps: reps, rpe: rpe)
                let diagonal = try ratedWorkingSet(weight, reps: reps + 1, rpe: rpe + 1)
                // Anchored non-nil: every pair in this loop is inside the chart, so a comparison
                // that held because both sides were `nil` would be the test passing on nothing.
                #expect(formula.estimate(for: here) != nil)
                #expect(
                    formula.estimate(for: here) == formula.estimate(for: diagonal),
                    "\(reps) reps at RPE \(rpe) should match \(reps + 1) at RPE \(rpe + 1)")
            }
        }
    }

    @Test("The model answers for efforts the printed chart has no column for")
    func theModelReachesPastThePrintedGrid() throws {
        // A consequence of collapsing the grid to one axis, asserted so it is a decision rather
        // than something discovered later. The published chart is printed over RPE 6.5 – 10, so it
        // has no column for a single at RPE 1 — but that set is ten reps from failure, which is a
        // row the chart does have, and it resolves to the identical estimate as ten reps at RPE 10.
        //
        // Refusing it would mean storing the printed rectangle *as well as* the sequence, purely to
        // decline efforts the model answers perfectly well. `SetRecord` already bounds RPE to 1...10
        // and `repRange` bounds the rep axis; nothing else is claimed.
        let formula = RPEBased()
        let weight = Weight(grams: 100_000)
        let offGrid = try ratedWorkingSet(weight, reps: 1, rpe: 1)
        let onGrid = try ratedWorkingSet(weight, reps: 10, rpe: 10)
        #expect(formula.estimate(for: offGrid) != nil)
        #expect(formula.estimate(for: offGrid) == formula.estimate(for: onGrid))
        // The lowest RPE the chart is actually printed at, for contrast — same row, in the grid.
        #expect(formula.estimate(for: offGrid) == Weight(grams: 135_318))
    }

    @Test("The percentages fall strictly as the effort gets easier")
    func percentagesDecreaseMonotonically() {
        // Not enforced by `RPETable.init` — it is a judgement that would reject a legitimate
        // replacement chart — so it is asserted here, against the chart that actually ships.
        var previous = Double.infinity
        for entry in RPETable.standardEntries {
            #expect(entry.fractionOfMax < previous, "row \(entry.repsToFailure) does not fall")
            previous = entry.fractionOfMax
        }
    }

    @Test("The shipped rows pass the validating initialiser")
    func shippedRowsAreValid() {
        // `standard` is built through a private unchecked initialiser, because unwrapping the
        // failable one at a `static let` would need a force unwrap. This is where the guarantee
        // actually lives: the same rows, through the same guards.
        let validated = RPETable(entries: RPETable.standardEntries, repRange: 1...10)
        #expect(validated != nil)
        #expect(validated == RPETable.standard)
        #expect(RPETable.standardEntries.count == 26)
    }

    @Test("A single at RPE 10 is 100%, so it returns the lifted weight exactly")
    func oneRepAtRPETenIsTheLiftedWeight() throws {
        // The chart's anchor, and the one cell that needs no source to check: a maximal single is
        // by definition a one-rep maximum. Exact rather than near — the fraction is 1.0, so the
        // multiplier is exactly 1 and the round trip through `Double` costs nothing.
        let formula = RPEBased()
        for grams in [100_000, 60_000, 227_500, 1] {
            let weight = Weight(grams: grams)
            #expect(formula.estimate(for: try ratedWorkingSet(weight, reps: 1, rpe: 10)) == weight)
        }
    }

    @Test("Hand-computed estimates for a 100 kg lift")
    func handComputedGramValues() throws {
        // Five cells worked out by hand from the percentages above — 100 000 g ÷ the fraction,
        // rounded to the nearest gram. Exact equality: every one of these sits far from a rounding
        // boundary, which was checked rather than hoped for.
        let formula = RPEBased()
        let weight = Weight(grams: 100_000)
        #expect(formula.estimate(for: try ratedWorkingSet(weight, reps: 2, rpe: 10)) == Weight(grams: 104_712))
        #expect(formula.estimate(for: try ratedWorkingSet(weight, reps: 3, rpe: 9)) == Weight(grams: 112_108))
        #expect(formula.estimate(for: try ratedWorkingSet(weight, reps: 5, rpe: 8)) == Weight(grams: 123_305))
        #expect(formula.estimate(for: try ratedWorkingSet(weight, reps: 10, rpe: 6.5)) == Weight(grams: 156_740))
        #expect(formula.estimate(for: try ratedWorkingSet(weight, reps: 1, rpe: 10)) == Weight(grams: 100_000))
    }

    @Test("An off-step RPE interpolates between two real rows")
    func offStepRPEInterpolates() throws {
        // `SetRecord` accepts 8.25 on purpose, and the chart has no cell for it: 2 reps at RPE 8.25
        // is 3.75 from failure, midway between the rows at 3.5 (90.7%) and 4 (89.2%), so 89.95%.
        let formula = RPEBased()
        let set = try ratedWorkingSet(Weight(grams: 100_000), reps: 2, rpe: 8.25)
        #expect(formula.estimate(for: set) == Weight(grams: 111_173))
    }

    @Test("The rep range is the chart's columns, which coincides with the five by another route")
    func repRangeIsTheChartsColumns() throws {
        let formula = RPEBased()
        #expect(formula.validRepRange == 1...10)
        // Equal to `tabulatedRepRange` and not read from it: that constant is where five equations
        // stop agreeing, this is how wide the chart is printed. A sourced replacement may differ.
        #expect(formula.validRepRange == E1RMFormulaID.tabulatedRepRange)
        #expect(formula.estimate(for: try ratedWorkingSet(Weight(grams: 100_000), reps: 11, rpe: 10)) == nil)
    }

    @Test("An effort past the last row has no estimate, inside the rep range or not")
    func beyondTheLastRowIsNil() throws {
        // 10 reps at RPE 6 is 14 from failure and the chart stops at 13.5. The rep count is
        // perfectly valid, so this is the chart declining rather than the rep-range guard — the
        // two refusals stay distinguishable on the real table, not just on a fixture.
        let formula = RPEBased()
        let set = try ratedWorkingSet(Weight(grams: 100_000), reps: 10, rpe: 6)
        #expect(formula.validRepRange.contains(set.reps))
        #expect(formula.estimate(for: set) == nil)
        #expect(formula.estimate(for: try ratedWorkingSet(Weight(grams: 100_000), reps: 10, rpe: 6.5)) != nil)
    }

    @Test("The default initialiser reads the standard chart")
    func defaultInitialiserUsesTheStandardChart() {
        #expect(RPEBased().table == RPETable.standard)
        #expect(RPEBased().id == .rpeBased)
    }
}
