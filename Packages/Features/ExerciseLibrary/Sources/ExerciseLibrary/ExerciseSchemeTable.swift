import DerivedValues
import Foundation
import PowerliftingCore

/// `FR-16.2.4`'s table: one exercise's records laid out as rep counts by set counts.
///
/// **A value rather than a pile of filters on a view**, on ``ExerciseRecordList``'s rule and for its
/// reason — which rows and columns a table has, and which cells are blank, is the claim worth
/// asserting and it can be asserted without rendering anything.
///
/// **Only the rows and columns that hold something are drawn, and under `FR-17.2.1` that rule is
/// what makes the table worth reading.** The full shape is `1...10` reps by `1...6` sets, which is
/// sixty cells, and a lifter who has only ever performed singles would read five blank columns as a
/// table that failed to load. Filtering to the rows and columns something stands in leaves a small
/// grid whose blanks are *near misses* rather than noise: a lifter who has done `5 × 5` and `3 × 3`
/// gets a two-by-two with two empty corners, and those two corners are the interesting cells —
/// schemes adjacent to what they train and never performed.
///
/// **So a cell absent from a drawn row is drawn, not skipped.** Under the withdrawn dominance rule
/// a blank inside a drawn row could only be a scheme the lifter's own heavier work had blocked, and
/// leaving it empty was right; under `FR-17.2.1` it means never performed, which is one of
/// `FR-17.2.2`'s three states and has to be said in a word (`G-4.5`). ``state(at:)`` is where all
/// three are answered.
struct ExerciseSchemeTable: Equatable {
    /// Every rep count a scheme record can stand at (`FR-1.6.1`).
    static let repRange = PersonalRecords.repRange

    /// Every set count one can (`FR-17.2.1`).
    static let setRange = SchemeRecordCalculator.setRange

    /// The cells, keyed by scheme.
    let cells: [RecordScheme: DatedSchemeRecord]

    /// The rep counts that hold at least one record, ascending — the table's rows.
    let repCounts: [Int]

    /// The set counts that do, ascending — its columns.
    let setCounts: [Int]

    /// Lays one exercise's records out.
    ///
    /// - Parameter records: What the recompute produced, in any order. Anything outside the two
    ///   ranges is dropped rather than trusted: the calculator clamps, so a cell beyond them is a
    ///   row this build did not write.
    init(_ records: [DatedSchemeRecord]) {
        let inside = records.filter {
            Self.repRange.contains($0.scheme.reps) && Self.setRange.contains($0.scheme.sets)
        }
        cells = Dictionary(inside.map { ($0.scheme, $0) }, uniquingKeysWith: { first, _ in first })
        repCounts = Self.repRange.filter { reps in inside.contains { $0.scheme.reps == reps } }
        setCounts = Self.setRange.filter { sets in inside.contains { $0.scheme.sets == sets } }
    }

    /// Whether this exercise holds no record at any scheme.
    var isEmpty: Bool { cells.isEmpty }

    /// One cell, or `nil` where no run reached it.
    ///
    /// - Parameter scheme: The cell.
    /// - Returns: The record, or `nil`.
    func record(at scheme: RecordScheme) -> DatedSchemeRecord? { cells[scheme] }

    /// Which of `FR-17.2.2`'s three states a cell is in.
    ///
    /// **A value rather than two `if`s in the grid's body**, on this type's own rule: which state a
    /// cell draws is the claim worth asserting, and it can be asserted without rendering anything.
    ///
    /// - Parameter scheme: The cell.
    /// - Returns: Its state.
    func state(at scheme: RecordScheme) -> CellState {
        guard let record = cells[scheme] else { return .neverPerformed }
        return record.previous == nil ? .firstPerformance(record) : .record(record)
    }

    /// What one cell of the table is (`FR-17.2.2`).
    enum CellState: Equatable {
        /// A run at this scheme beat an earlier run at this scheme.
        case record(DatedSchemeRecord)

        /// `FR-16.2.3`'s baseline — performed once, with nothing beaten.
        case firstPerformance(DatedSchemeRecord)

        /// No run was ever performed at this scheme.
        case neverPerformed
    }

    /// `FR-16.2.4`'s glance: the schemes whose reps and sets are equal — `2 × 2`, `3 × 3` — that
    /// this exercise holds, ascending.
    ///
    /// **`1 × 1` is excluded, and that is where the diagonal meets the rep-max row.** The one-set
    /// column *is* `FR-1.6.1`'s ten rep maxes, which the detail section already draws in full; a
    /// diagonal beginning at `1 × 1` would put the 1RM on the same screen twice, under two
    /// spellings, which reads as two different records rather than one seen twice.
    ///
    /// **Only cells that were performed**, records and baselines alike: the diagonal is a glance at
    /// what the lifter has done, and a never-performed cell has no load to show on a row of loads.
    var diagonal: [DatedSchemeRecord] {
        Self.setRange.dropFirst().compactMap { cells[RecordScheme(reps: $0, sets: $0)] }
    }
}
