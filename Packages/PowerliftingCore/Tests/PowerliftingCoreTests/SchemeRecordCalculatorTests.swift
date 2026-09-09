import Testing

@testable import PowerliftingCore

/// `FR-17.2.1`'s performed-only rule and `FR-16.2.3`'s beaten load, over runs a caller has already
/// grouped.
@Suite("Scheme records")
struct SchemeRecordCalculatorTests {
    /// One run, positioned at `offset` in the collection the caller supplied.
    private func run(_ grams: Int, _ reps: Int, by count: Int, at offset: Int = 0) -> SetRun {
        SetRun(weight: Weight(grams: grams), reps: reps, count: count, setOffset: offset)
    }

    /// The record at one cell, or `nil`.
    private func record(_ records: [SchemeRecord], reps: Int, sets: Int) -> SchemeRecord? {
        records.first { $0.scheme == RecordScheme(reps: reps, sets: sets) }
    }

    // MARK: - FR-17.2.1, one cell per run

    /// `DOD-17.2`'s calculator half, and the whole of what `D-17.2` changed: the run fills its own
    /// cell and every cell the withdrawn dominance rule would have filled stays empty.
    @Test("A five-by-five fills the 5×5 cell and no other")
    func oneRunFillsOneCell() {
        let records = SchemeRecordCalculator().records(in: [run(100_000, 5, by: 5)])

        #expect(records.count == 1)
        #expect(record(records, reps: 5, sets: 5)?.weight == Weight(grams: 100_000))
        // The four corners of the rectangle the dominance rule used to claim.
        #expect(record(records, reps: 1, sets: 1) == nil)
        #expect(record(records, reps: 5, sets: 1) == nil)
        #expect(record(records, reps: 1, sets: 5) == nil)
        #expect(record(records, reps: 3, sets: 3) == nil)
        #expect(record(records, reps: 6, sets: 1) == nil)
    }

    /// `DOD-17.3`: a single set of eight is the 8-rep record, and the 5-rep cell reads as never
    /// performed rather than as an implied record at the same load.
    @Test("A set of eight fills the 8-rep cell only")
    func aSingleFillsItsOwnRepCell() {
        let records = SchemeRecordCalculator().records(in: [run(145_000, 8, by: 1)])

        #expect(records.count == 1)
        #expect(record(records, reps: 8, sets: 1)?.weight == Weight(grams: 145_000))
        #expect(record(records, reps: 5, sets: 1) == nil)
        #expect(record(records, reps: 1, sets: 1) == nil)
    }

    /// The task's own worked example: two runs at different schemes are two records, and neither is
    /// evidence about the cell the other names or about the two cells between them.
    @Test("Two runs at two schemes hold two cells, and the cross terms stay empty")
    func twoRunsHoldTwoCells() {
        let records = SchemeRecordCalculator().records(in: [
            run(90_000, 5, by: 4, at: 0),
            run(90_000, 4, by: 1, at: 4),
        ])

        #expect(records.count == 2)
        #expect(record(records, reps: 5, sets: 4)?.weight == Weight(grams: 90_000))
        #expect(record(records, reps: 4, sets: 1)?.weight == Weight(grams: 90_000))
        #expect(record(records, reps: 4, sets: 5) == nil)
        #expect(record(records, reps: 5, sets: 1) == nil)
        #expect(record(records, reps: 4, sets: 4) == nil)
    }

    /// A heavier run at a *different* scheme leaves the standing one alone, where the dominance rule
    /// would have taken every cell beneath it.
    @Test("A heavier shorter run takes its own cell and nothing standing")
    func aHeavierRunTakesOnlyItsOwnCell() {
        let records = SchemeRecordCalculator().records(in: [
            run(100_000, 5, by: 5, at: 0),
            run(105_000, 5, by: 3, at: 5),
            run(100_000, 6, by: 1, at: 8),
        ])

        #expect(records.count == 3)
        #expect(record(records, reps: 5, sets: 3)?.weight == Weight(grams: 105_000))
        #expect(record(records, reps: 5, sets: 5)?.weight == Weight(grams: 100_000))
        #expect(record(records, reps: 6, sets: 1)?.weight == Weight(grams: 100_000))
        #expect(record(records, reps: 1, sets: 1) == nil)
        #expect(record(records, reps: 5, sets: 4) == nil)
    }

    @Test("A run past either bound clamps rather than being refused")
    func boundsClamp() {
        let records = SchemeRecordCalculator().records(in: [run(80_000, 12, by: 8)])

        #expect(records.count == 1)
        #expect(record(records, reps: 10, sets: 6)?.weight == Weight(grams: 80_000))
        #expect(record(records, reps: 12, sets: 8) == nil)
        #expect(record(records, reps: 10, sets: 1) == nil)
    }

    /// `SetRecord.repsRange` starts at zero, so a completed working set of no reps is storable —
    /// and it is a record at no scheme at all.
    @Test("A run of zero reps sets nothing")
    func zeroRepsSetsNothing() {
        #expect(SchemeRecordCalculator().records(in: [run(100_000, 0, by: 3)]).isEmpty)
    }

    @Test("Nothing in, nothing out")
    func noRunsNoRecords() {
        #expect(SchemeRecordCalculator().records(in: []).isEmpty)
    }

    /// The history that used to produce a staircase: a heavy single and a volume run now hold one
    /// cell each, and the cells between them are nobody's.
    @Test("A heavy single blocks nothing, because it was never in the volume run's way")
    func aHeavySingleBlocksNothing() {
        let records = SchemeRecordCalculator().records(in: [
            run(140_000, 1, by: 1, at: 0),
            run(100_000, 5, by: 5, at: 1),
        ])

        #expect(records.count == 2)
        #expect(record(records, reps: 1, sets: 1)?.weight == Weight(grams: 140_000))
        #expect(record(records, reps: 5, sets: 5)?.weight == Weight(grams: 100_000))
        #expect(records.filter { $0.setOffset == 1 }.count == 1)
    }

    // MARK: - FR-16.2.3, the load a record beat

    /// `DOD-17.2`: `90 × 5 × 5` after `80 × 5 × 5` is one record at `5×5`, previous 80, and no other
    /// cell moved.
    @Test("The first run at a scheme is a baseline; the next heavier one carries what it beat")
    func baselineThenImprovement() {
        let records = SchemeRecordCalculator().records(in: [
            run(80_000, 5, by: 5, at: 0),
            run(90_000, 5, by: 5, at: 5),
        ])

        #expect(records.count == 1)
        #expect(record(records, reps: 5, sets: 5)?.weight == Weight(grams: 90_000))
        #expect(record(records, reps: 5, sets: 5)?.previousWeight == Weight(grams: 80_000))
        #expect(record(records, reps: 5, sets: 5)?.setOffset == 5)
    }

    @Test("A first-ever run is a baseline at the cell it fills")
    func aFirstRunIsABaseline() {
        let records = SchemeRecordCalculator().records(in: [run(100_000, 5, by: 5)])

        #expect(records.count == 1)
        #expect(record(records, reps: 5, sets: 5)?.previousWeight == nil)
        #expect(record(records, reps: 5, sets: 5)?.weight == Weight(grams: 100_000))
    }

    /// The state a screen has to tell from a baseline and from a record: a cell nothing reached is
    /// absent, not present at zero (`FR-17.2.2`).
    @Test("A scheme never performed is absent from the table entirely")
    func aSchemeNeverPerformedIsAbsent() {
        let records = SchemeRecordCalculator().records(in: [run(100_000, 5, by: 5)])

        #expect(!records.contains { $0.scheme == RecordScheme(reps: 3, sets: 3) })
        #expect(record(records, reps: 3, sets: 3) == nil)
    }

    /// The tie-break, and the half of it that is easy to lose: an equal load neither takes the cell
    /// **nor** becomes the load the standing record beat.
    @Test("An equal load is not a record and does not become a beaten load")
    func anEqualLoadIsNotARecord() {
        let records = SchemeRecordCalculator().records(in: [
            run(100_000, 5, by: 5, at: 0),
            run(100_000, 5, by: 5, at: 5),
        ])

        #expect(record(records, reps: 5, sets: 5)?.setOffset == 0)
        #expect(record(records, reps: 5, sets: 5)?.previousWeight == nil)
    }

    @Test("A lighter later run moves nothing")
    func aLighterRunMovesNothing() {
        let records = SchemeRecordCalculator().records(in: [
            run(105_000, 5, by: 5, at: 0),
            run(100_000, 5, by: 5, at: 5),
        ])

        #expect(record(records, reps: 5, sets: 5)?.weight == Weight(grams: 105_000))
        #expect(record(records, reps: 5, sets: 5)?.setOffset == 0)
        #expect(record(records, reps: 5, sets: 5)?.previousWeight == nil)
    }

    /// Three improvements in a row: a cell remembers the load it *actually* beat, not the first one
    /// it ever held.
    @Test("A beaten load is the one standing at the moment, not the oldest one")
    func theBeatenLoadIsTheOneItReplaced() {
        let records = SchemeRecordCalculator().records(in: [
            run(100_000, 5, by: 3, at: 0),
            run(105_000, 5, by: 3, at: 3),
            run(110_000, 5, by: 3, at: 6),
        ])

        #expect(record(records, reps: 5, sets: 3)?.weight == Weight(grams: 110_000))
        #expect(record(records, reps: 5, sets: 3)?.previousWeight == Weight(grams: 105_000))
    }

    /// Assisted work runs negative, and `Comparable` ranks −20 kg below −10 kg — so the *less*
    /// assisted attempt is the record, and a beaten load of a real zero is not a baseline.
    @Test("Assisted work sets scheme records, and zero is a real beaten load")
    func assistedWorkRanksByLoad() {
        let records = SchemeRecordCalculator().records(in: [
            run(-20_000, 5, by: 3, at: 0),
            run(0, 5, by: 3, at: 3),
            run(10_000, 5, by: 3, at: 6),
        ])

        #expect(record(records, reps: 5, sets: 3)?.weight == Weight(grams: 10_000))
        #expect(record(records, reps: 5, sets: 3)?.previousWeight == Weight(grams: 0))
        #expect(record(records, reps: 5, sets: 3)?.isBaselineForTest == false)
    }

    // MARK: - The shape of the answer

    @Test("The table comes back ascending by scheme")
    func theTableIsOrdered() {
        let records = SchemeRecordCalculator().records(in: [
            run(100_000, 3, by: 2, at: 0),
            run(120_000, 1, by: 1, at: 2),
            run(90_000, 3, by: 1, at: 3),
        ])

        #expect(
            records.map(\.scheme) == [
                RecordScheme(reps: 1, sets: 1),
                RecordScheme(reps: 3, sets: 1), RecordScheme(reps: 3, sets: 2),
            ])
    }

    /// `FR-16.2.1`: the N-rep max is the `sets == 1` column of this table, so the two must agree on
    /// the same sets — asserted against `PersonalRecordCalculator`, which is `FR-1.6.1`'s own
    /// definition. Both are exact reps since `D-17.2`, and this is the test that would fail if only
    /// one of them were moved.
    @Test("The one-set column is the N-rep max the rep-max calculator computes")
    func theOneSetColumnIsTheRepMax() {
        let sets = [
            SetRecord(weight: Weight(grams: 100_000), reps: 5, isWarmup: false, isCompleted: true),
            SetRecord(weight: Weight(grams: 120_000), reps: 2, isWarmup: false, isCompleted: true),
            SetRecord(weight: Weight(grams: 90_000), reps: 8, isWarmup: false, isCompleted: true),
        ].compactMap { $0 }
        let runs = sets.enumerated().map {
            SetRun(weight: $0.element.weight, reps: $0.element.reps, count: 1, setOffset: $0.offset)
        }
        let calculator = PersonalRecordCalculator()

        let column = SchemeRecordCalculator().records(in: runs).filter { $0.scheme.sets == 1 }

        #expect(column.count == 3)
        for record in column {
            let repMax = calculator.repMax(forReps: record.scheme.reps, in: sets)
            #expect(repMax?.weight == record.weight)
            #expect(repMax?.setOffset == record.setOffset)
        }
        // Anchored, so the loop above cannot pass by comparing two absences.
        #expect(column.first { $0.scheme.reps == 2 }?.weight == Weight(grams: 120_000))
        #expect(column.first { $0.scheme.reps == 8 }?.weight == Weight(grams: 90_000))
        #expect(column.first { $0.scheme.reps == 5 }?.weight == Weight(grams: 100_000))
        // And the two calculators agree about an N nothing was performed at, which is the half an
        // agreement over present cells alone cannot see.
        #expect(!column.contains { $0.scheme.reps == 1 })
        #expect(calculator.repMax(forReps: 1, in: sets) == nil)
    }
}

extension SchemeRecord {
    /// Whether this record has no beaten load — spelled out here rather than on the type, since
    /// `DerivedValues` is where a screen asks the question.
    fileprivate var isBaselineForTest: Bool { previousWeight == nil }
}

/// `FR-16.2.4` — which cell a badge names, given the cells a run holds.
@Suite("Maximal scheme")
struct MaximalSchemeTests {
    /// **The choice is trivial for one run, and that is the point worth pinning.** Since
    /// `FR-17.2.1` a run holds one cell, so every production caller hands `maximal(of:)` a
    /// single-element sequence or an empty one; the rule below it survives because the cache is not
    /// the calculator, and a restored backup can still name one set several times.
    @Test("One run holds one cell, so the maximal scheme is that cell")
    func theMaximalSchemeOfOneRunIsItsOnlyCell() {
        let held = SchemeRecordCalculator()
            .records(in: [SetRun(weight: Weight(grams: 100_000), reps: 5, count: 3, setOffset: 0)])

        #expect(held.count == 1)
        #expect(RecordScheme.maximal(of: held.map(\.scheme)) == RecordScheme(reps: 5, sets: 3))
    }

    /// **The product, not the order.** `<` puts `10 × 1` above `5 × 3` because it compares reps
    /// first; the badge names the larger performance, which is fifteen reps rather than ten.
    @Test("Reps times sets decides, where the scheme order would not")
    func theProductDecidesRatherThanTheOrder() {
        let ten = RecordScheme(reps: 10, sets: 1)
        let fifteen = RecordScheme(reps: 5, sets: 3)

        #expect(ten > fifteen)
        #expect(RecordScheme.maximal(of: [ten, fifteen]) == fifteen)
    }

    /// A tie in the product is broken by the order, so the answer is one scheme rather than
    /// whichever the collection happened to yield first.
    @Test("A tie in the product falls back to the scheme order")
    func aTieFallsBackToTheOrder() {
        let sixByOne = RecordScheme(reps: 6, sets: 1)
        let twoByThree = RecordScheme(reps: 2, sets: 3)

        #expect(RecordScheme.maximal(of: [twoByThree, sixByOne]) == sixByOne)
        #expect(RecordScheme.maximal(of: [sixByOne, twoByThree]) == sixByOne)
    }

    /// No cells is no badge, which is the ordinary case on every row that is not a record.
    @Test("No schemes is no maximal one")
    func noSchemesIsNoMaximalOne() {
        #expect(RecordScheme.maximal(of: [RecordScheme]()) == nil)
    }
}
