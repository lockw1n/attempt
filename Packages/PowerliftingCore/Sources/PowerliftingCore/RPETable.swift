/// The RPE/RIR → %1RM chart an ``RPEBased`` estimate reads (`TR-0.2.4`).
///
/// **Data, not a switch statement.** `TR-0.5.2` delivers a replacement over
/// `/content/v1/formulas.json`, so swapping the chart is constructing a different value — no call
/// site changes and no case is added anywhere.
///
/// **One sequence, not a grid.** Every cell of the conventional chart depends only on
/// `reps + reps in reserve`: a 3-rep set at RPE 9 and a 4-rep set at RPE 10 are the same cell, both
/// being four reps from failure. Keying on that sum is what the chart already is, so the table
/// stores a single ascending sequence and ``RPEBased`` computes the key.
///
/// **A consequence worth knowing: this answers for efforts the printed chart has no column for.**
/// A chart is printed over a rectangle of reps × RPE, but the key collapses that to one axis, so
/// any pair summing into ``entries``' extent gets a cell — including pairs outside the printed
/// rectangle. A single at RPE 1 is ten reps from failure and resolves to the same row as ten reps
/// at RPE 10. That follows from the model, not from the source, and it is deliberate: refusing it
/// would mean storing the printed rectangle as well as the sequence, to decline efforts the model
/// answers perfectly well. ``repRange`` still bounds the rep axis.
public struct RPETable: Sendable, Hashable {
    /// One row of the chart: how far from failure the set was, and what fraction of a maximum that
    /// corresponds to.
    public struct Entry: Sendable, Hashable {
        /// Reps performed plus reps left in reserve — the reps the set would have reached at
        /// failure.
        ///
        /// A `Double` because the RPE scale is: a half-point RPE puts the key on a half rep. Half
        /// values are exactly representable, so a conventional entry lands on a key exactly rather
        /// than within a tolerance.
        public let repsToFailure: Double

        /// The load as a fraction of a one-rep maximum — `0.837` for a chart's "83.7%".
        ///
        /// A fraction rather than the published percentage, so it reads as the dimensionless ratio
        /// it is and cannot be mistaken for a mass (`G-1.1`).
        public let fractionOfMax: Double

        /// Creates one row. See ``RPETable/init(entries:repRange:)`` for what is rejected.
        public init(repsToFailure: Double, fractionOfMax: Double) {
            self.repsToFailure = repsToFailure
            self.fractionOfMax = fractionOfMax
        }
    }

    /// The chart's rows, in strictly ascending ``Entry/repsToFailure`` order.
    public let entries: [Entry]

    /// The rep counts this chart will answer for.
    ///
    /// Carried as data rather than shared with the closed-form five: it is the extent of this
    /// chart's columns, which is a fact about the chart, and a replacement declares its own. It is
    /// **not** implied by ``entries`` — a chart may tabulate a key that no column of it reaches.
    public let repRange: ClosedRange<Int>

    /// Creates a chart, or returns `nil` if the rows could not have come from one.
    ///
    /// - Parameters:
    ///   - entries: At least one row, strictly ascending in ``Entry/repsToFailure``. Strict rather
    ///     than merely sorted, because two rows sharing a key make the value at that key ambiguous
    ///     and leave interpolation dividing by zero.
    ///   - repRange: The rep counts the chart covers. Must start at 1 or above.
    /// - Returns: `nil` if `entries` is empty, if any value is not finite, if the keys do not
    ///   strictly ascend, if a fraction falls outside `0 < fraction ≤ 1`, or if `repRange` starts
    ///   below 1.
    ///
    ///   The fraction's upper bound is worth its line: a row authored as `83.7` rather than `0.837`
    ///   is the likeliest way to get this type wrong, and it would otherwise produce estimates a
    ///   hundredfold too light in silence. The rep floor is worth its line for the opposite reason —
    ///   it is the one guard a *remote* chart could trip (`TR-0.5.2`). A zero-rep set is legal
    ///   (`FR-1.2.5`) and carries no information about a maximum, and no cell of a chart can mean
    ///   "reps to failure: none", so a chart claiming to cover 0 reps is malformed rather than
    ///   unusual.
    public init?(entries: [Entry], repRange: ClosedRange<Int>) {
        guard !entries.isEmpty, repRange.lowerBound >= 1 else { return nil }
        var previous: Double?
        for entry in entries {
            guard entry.repsToFailure.isFinite, entry.fractionOfMax.isFinite else { return nil }
            guard entry.fractionOfMax > 0, entry.fractionOfMax <= 1 else { return nil }
            if let previous, entry.repsToFailure <= previous { return nil }
            previous = entry.repsToFailure
        }
        self.entries = entries
        self.repRange = repRange
    }

    /// The fraction of a maximum this chart gives `repsToFailure` reps from failure.
    ///
    /// A key between two rows is **interpolated linearly in the fraction**. That is a choice — the
    /// multiplier is the reciprocal, so interpolating it instead would give a slightly different
    /// answer — and this way round is the one that reads as "between these two cells of the chart".
    ///
    /// - Parameter repsToFailure: Reps performed plus reps in reserve.
    /// - Returns: `nil` past either end of the chart. Not extrapolated: a chart fitted over its own
    ///   range says nothing outside it, and extending the line produces a confident number at
    ///   exactly the efforts a lifter reads most closely.
    public func fractionOfMax(atRepsToFailure repsToFailure: Double) -> Double? {
        guard let upperIndex = entries.firstIndex(where: { $0.repsToFailure >= repsToFailure }) else {
            return nil
        }
        let upper = entries[upperIndex]
        if upper.repsToFailure == repsToFailure { return upper.fractionOfMax }
        guard upperIndex > entries.startIndex else { return nil }

        let lower = entries[upperIndex - 1]
        let span = upper.repsToFailure - lower.repsToFailure
        let position = (repsToFailure - lower.repsToFailure) / span
        return lower.fractionOfMax + position * (upper.fractionOfMax - lower.fractionOfMax)
    }
}
