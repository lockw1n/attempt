import DerivedValues
import Foundation
import PowerliftingCore

/// `FR-16.2.4`'s table: one exercise's records laid out as rep counts by set counts.
///
/// **A value rather than a pile of filters on a view**, on ``ExerciseRecordList``'s rule and for its
/// reason — which rows and columns a table has, and which cells are blank, is the claim worth
/// asserting and it can be asserted without rendering anything.
///
/// **Only the rows and columns that hold something are drawn.** The table's shape is `1...10` reps
/// by `1...6` sets, which is sixty cells, and a lifter who has only ever performed singles would
/// otherwise read five blank columns as a table that failed to load. A row or column absent here is
/// one with no record in it at all; a *cell* absent from a drawn row is `FR-16.2.1`'s blank — a
/// scheme never performed, which is not the same as a load of zero (`Weight` is signed).
struct ExerciseSchemeTable: Equatable {
    /// Every rep count a scheme record can stand at (`FR-1.6.1`).
    static let repRange = PersonalRecords.repRange

    /// Every set count one can (`FR-16.2.2`).
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

    /// `FR-16.2.4`'s glance: the schemes whose reps and sets are equal — `2 × 2`, `3 × 3` — that
    /// this exercise holds, ascending.
    ///
    /// **`1 × 1` is excluded, and that is where the diagonal meets the rep-max row.** The one-set
    /// column *is* `FR-1.6.1`'s ten rep maxes, which the detail section already draws in full; a
    /// diagonal beginning at `1 × 1` would put the 1RM on the same screen twice, under two
    /// spellings, which reads as two different records rather than one seen twice.
    var diagonal: [DatedSchemeRecord] {
        Self.setRange.dropFirst().compactMap { cells[RecordScheme(reps: $0, sets: $0)] }
    }
}
