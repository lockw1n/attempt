import Testing

@testable import PowerliftingCore

/// `FR-16.2.2`'s dominance rule and `FR-16.2.3`'s beaten load, over runs a caller has already
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

    // MARK: - FR-16.2.2, dominance in two dimensions

    @Test("A five-by-five fills every cell at or below it, and no cell above it")
    func oneRunFillsItsRectangle() {
        let records = SchemeRecordCalculator().records(in: [run(100_000, 5, by: 5)])

        #expect(records.count == 25)
        #expect(records.allSatisfy { $0.weight == Weight(grams: 100_000) })
        #expect(records.allSatisfy { $0.scheme.reps <= 5 && $0.scheme.sets <= 5 })
        #expect(record(records, reps: 5, sets: 5)?.weight == Weight(grams: 100_000))
        #expect(record(records, reps: 1, sets: 1)?.weight == Weight(grams: 100_000))
        #expect(record(records, reps: 6, sets: 1) == nil)
        #expect(record(records, reps: 1, sets: 6) == nil)
    }

    /// The task's own worked example, in one sequence: a heavier but shorter run takes the cells it
    /// dominates and leaves the rest standing, and a run reaching a new rep count takes only the
    /// cells nothing had reached.
    @Test("A heavier shorter run takes only the cells it dominates")
    func laterRunsTakeOnlyWhatTheyDominate() {
        let records = SchemeRecordCalculator().records(in: [
            run(100_000, 5, by: 5, at: 0),
            run(105_000, 5, by: 3, at: 5),
            run(100_000, 6, by: 1, at: 8),
        ])

        #expect(record(records, reps: 5, sets: 3)?.weight == Weight(grams: 105_000))
        #expect(record(records, reps: 1, sets: 1)?.weight == Weight(grams: 105_000))
        #expect(record(records, reps: 5, sets: 4)?.weight == Weight(grams: 100_000))
        #expect(record(records, reps: 5, sets: 5)?.weight == Weight(grams: 100_000))
        // The 6-rep single reaches a rep count nothing had reached, at one set only.
        #expect(record(records, reps: 6, sets: 1)?.weight == Weight(grams: 100_000))
        #expect(record(records, reps: 6, sets: 2) == nil)
    }

    @Test("A run past either bound clamps rather than being refused")
    func boundsClamp() {
        let records = SchemeRecordCalculator().records(in: [run(80_000, 12, by: 8)])

        #expect(records.count == 60)
        #expect(records.map(\.scheme.reps).max() == 10)
        #expect(records.map(\.scheme.sets).max() == 6)
        #expect(record(records, reps: 10, sets: 6)?.weight == Weight(grams: 80_000))
        #expect(record(records, reps: 11, sets: 1) == nil)
        #expect(record(records, reps: 1, sets: 7) == nil)
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

    // MARK: - FR-16.2.3, the load a record beat

    @Test("The first run at a scheme is a baseline; the next heavier one carries what it beat")
    func baselineThenImprovement() {
        let records = SchemeRecordCalculator().records(in: [
            run(100_000, 5, by: 5, at: 0),
            run(105_000, 5, by: 5, at: 5),
        ])

        #expect(record(records, reps: 5, sets: 5)?.weight == Weight(grams: 105_000))
        #expect(record(records, reps: 5, sets: 5)?.previousWeight == Weight(grams: 100_000))
        #expect(records.allSatisfy { $0.previousWeight == Weight(grams: 100_000) })
    }

    @Test("A first-ever run is a baseline at every cell it fills")
    func aFirstRunIsABaseline() {
        let records = SchemeRecordCalculator().records(in: [run(100_000, 5, by: 5)])

        #expect(records.allSatisfy { $0.previousWeight == nil })
        #expect(record(records, reps: 5, sets: 5)?.previousWeight == nil)
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
        let records = SchemeRecordCalculator().records(in: [run(100_000, 3, by: 2)])

        #expect(
            records.map(\.scheme) == [
                RecordScheme(reps: 1, sets: 1), RecordScheme(reps: 1, sets: 2),
                RecordScheme(reps: 2, sets: 1), RecordScheme(reps: 2, sets: 2),
                RecordScheme(reps: 3, sets: 1), RecordScheme(reps: 3, sets: 2),
            ])
    }

    /// `FR-16.2.1`: the N-rep max is the `sets == 1` column of this table, so the two must agree on
    /// the same sets — asserted against `PersonalRecordCalculator`, which is the definition
    /// `FR-1.6.1` already shipped.
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

        #expect(column.count == 8)
        for record in column {
            let repMax = calculator.repMax(forReps: record.scheme.reps, in: sets)
            #expect(repMax?.weight == record.weight)
            #expect(repMax?.setOffset == record.setOffset)
        }
        // Anchored, so the loop above cannot pass by comparing two absences.
        #expect(column.first { $0.scheme.reps == 2 }?.weight == Weight(grams: 120_000))
        #expect(column.first { $0.scheme.reps == 8 }?.weight == Weight(grams: 90_000))
    }
}

extension SchemeRecord {
    /// Whether this record has no beaten load — spelled out here rather than on the type, since
    /// `DerivedValues` is where a screen asks the question.
    fileprivate var isBaselineForTest: Bool { previousWeight == nil }
}
