import DerivedValues
import Foundation
import PowerliftingCore
import Testing

@testable import ExerciseLibrary

/// `FR-16.2.4` — what the record table's shape is, without rendering one.
@MainActor
@Suite("Exercise scheme table")
struct ExerciseSchemeTableTests {
    /// One cell, stated as briefly as the claim under test allows.
    private func cell(
        _ reps: Int, _ sets: Int, kilos: Double = 100, previous: Double? = nil
    ) -> DatedSchemeRecord {
        DatedSchemeRecord(
            scheme: RecordScheme(reps: reps, sets: sets),
            record: DatedRecord(
                weight: Weight(grams: Int(kilos * 1000)),
                sourceSetID: UUID(),
                achievedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            previous: previous.map { Weight(grams: Int($0 * 1000)) })
    }

    /// **A row or column with nothing in it is not drawn**, so a lifter who has only ever performed
    /// singles reads one column rather than five blank ones.
    @Test("Only the rep counts and set counts that hold a record become rows and columns")
    func emptyRowsAndColumnsAreNotDrawn() {
        let table = ExerciseSchemeTable([cell(1, 1), cell(2, 1), cell(5, 3)])

        #expect(table.repCounts == [1, 2, 5])
        #expect(table.setCounts == [1, 3])
    }

    /// A cell inside a drawn row that no run reached stays absent — `Weight` is signed, so a zero
    /// there would be a load the lifter actually lifted.
    @Test("A cell no run reached is absent rather than zero")
    func anUnreachedCellIsAbsent() {
        let table = ExerciseSchemeTable([cell(5, 1), cell(5, 3)])

        #expect(table.record(at: RecordScheme(reps: 5, sets: 1)) != nil)
        #expect(table.record(at: RecordScheme(reps: 5, sets: 2)) == nil)
    }

    /// **The table's own bounds, not the caller's.** A row outside `1...10 × 1...6` is one this
    /// build did not write, and drawing it would put a column beyond the six the calculator fills.
    @Test("A record outside the table's bounds is dropped rather than drawn")
    func recordsOutsideTheBoundsAreDropped() {
        let table = ExerciseSchemeTable([cell(11, 1), cell(5, 7), cell(5, 1)])

        #expect(table.repCounts == [5])
        #expect(table.setCounts == [1])
        #expect(table.cells.count == 1)
    }

    /// `FR-16.2.4`'s glance on the detail screen: the schemes whose reps and sets match.
    @Test("The diagonal is the matching cells, ascending")
    func theDiagonalIsTheMatchingCells() {
        let table = ExerciseSchemeTable([cell(2, 2), cell(5, 5), cell(5, 3), cell(3, 2)])

        #expect(table.diagonal.map(\.scheme) == [RecordScheme(reps: 2, sets: 2), RecordScheme(reps: 5, sets: 5)])
    }

    /// **`1 × 1` is left out of the diagonal deliberately**: the one-set column is the rep-max row
    /// the same section already draws in full, and a 1RM shown twice under two spellings reads as
    /// two records.
    @Test("The diagonal omits 1 × 1, which the rep-max row already carries")
    func theDiagonalOmitsTheSingle() {
        let table = ExerciseSchemeTable([cell(1, 1), cell(3, 3)])

        #expect(table.diagonal.map(\.scheme) == [RecordScheme(reps: 3, sets: 3)])
    }

    /// An exercise with nothing in the cache draws the insufficient-data state rather than an empty
    /// grid with headings.
    @Test("A table with no cells is empty")
    func aTableWithNoCellsIsEmpty() {
        #expect(ExerciseSchemeTable([]).isEmpty)
        #expect(!ExerciseSchemeTable([cell(1, 1)]).isEmpty)
    }
}
