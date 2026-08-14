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
public struct RPETable: Sendable, Hashable, Codable {
    /// One row of the chart: how far from failure the set was, and what fraction of a maximum that
    /// corresponds to.
    public struct Entry: Sendable, Hashable, Codable {
        /// Reps performed plus reps left in reserve — the reps the set would have reached at
        /// failure.
        ///
        /// A `Double` because the RPE scale is: a half-point RPE puts the key on a half rep. Half
        /// values are exactly representable, so a conventional entry lands on a key exactly rather
        /// than within a tolerance.
        ///
        /// Finite, and strictly ascending across a chart's ``RPETable/entries``. Both are enforced
        /// by ``RPETable/init(entries:repRange:)`` rather than here, since ordering is a fact about
        /// the sequence and not about one row.
        public let repsToFailure: Double

        /// The load as a fraction of a one-rep maximum — `0.837` for a chart's "83.7%".
        ///
        /// A fraction rather than the published percentage, so it reads as the dimensionless ratio
        /// it is and cannot be mistaken for a mass (`G-1.1`).
        ///
        /// Within `0 < fraction ≤ 1`, enforced by ``RPETable/init(entries:repRange:)``, whose note
        /// says why the upper bound is the one that catches a row authored as `83.7`.
        public let fractionOfMax: Double

        /// Creates one row. See ``RPETable/init(entries:repRange:)`` for what is rejected.
        public init(repsToFailure: Double, fractionOfMax: Double) {
            self.repsToFailure = repsToFailure
            self.fractionOfMax = fractionOfMax
        }
    }

    /// The chart's rows, in strictly ascending ``Entry/repsToFailure`` order.
    public let entries: [Entry]

    /// The rep counts this chart will answer for. Starts at 1 or above.
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
    /// - Parameter repsToFailure: Reps performed plus reps in reserve, conventionally a whole or
    ///   half rep. Any finite value; one falling between two rows is interpolated.
    /// - Returns: A dimensionless fraction within `0 < f ≤ 1`, since interpolating between two rows
    ///   of ``Entry/fractionOfMax`` cannot leave their bounds. `nil` past either end of the chart —
    ///   not extrapolated: a chart fitted over its own range says nothing outside it, and extending
    ///   the line produces a confident number at exactly the efforts a lifter reads most closely.
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

// MARK: - Codable

extension RPETable.Entry {
    /// `{"repsToFailure": 6, "fractionOfMax": 0.837}` — bare numbers, key spelling and order pinned
    /// the same way as ``RPETable``'s own keys.
    private enum CodingKeys: String, CodingKey {
        case repsToFailure
        case fractionOfMax
    }

    /// Hand-written for the same reason as ``RPETable``'s: the module's convention is that a wire
    /// shape's key order is a decision, not a side effect of synthesis. `Entry` alone has no
    /// invariant to protect — ``RPETable/init(entries:repRange:)`` is where the sequence is
    /// validated — so this conformance stores the two fields as given.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.repsToFailure = try container.decode(Double.self, forKey: .repsToFailure)
        self.fractionOfMax = try container.decode(Double.self, forKey: .fractionOfMax)
    }

    /// Writes the two fields in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(repsToFailure, forKey: .repsToFailure)
        try container.encode(fractionOfMax, forKey: .fractionOfMax)
    }
}

extension RPETable {
    /// The wire shape `TR-0.5.2` publishes at `/content/v1/formulas.json`: the sequence in
    /// ``entries`` order, plus ``repRange`` spelled as its two bounds since a `ClosedRange` has no
    /// shape of its own to encode. Declared rather than synthesised, following ``RoundingRule``'s
    /// precedent: key spelling and order are pinned, and decoding re-enters
    /// ``init(entries:repRange:)`` rather than trusting the bytes.
    private enum CodingKeys: String, CodingKey {
        case entries
        case repRangeLowerBound
        case repRangeUpperBound
    }

    /// Decodes the shape ``CodingKeys`` describes, refusing anything ``init(entries:repRange:)``
    /// would have refused.
    ///
    /// Hand-written for the reason every composite type in this module is: synthesised `Decodable`
    /// would build an `RPETable` directly from its stored properties, bypassing the ascending-key,
    /// finite-value and `0 < fraction ≤ 1` guards and hand a caller a table that divides by zero.
    /// The bounds are checked before ``ClosedRange`` is constructed from them — `lower...upper`
    /// **traps** rather than throwing when `lower > upper`, and a remote payload is exactly the
    /// input that guard exists for.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([Entry].self, forKey: .entries)
        let lowerBound = try container.decode(Int.self, forKey: .repRangeLowerBound)
        let upperBound = try container.decode(Int.self, forKey: .repRangeUpperBound)
        guard lowerBound <= upperBound else {
            throw DecodingError.dataCorruptedError(
                forKey: .repRangeUpperBound,
                in: container,
                debugDescription:
                    "RPETable repRangeUpperBound (\(upperBound)) must be >= repRangeLowerBound (\(lowerBound))."
            )
        }
        guard let table = RPETable(entries: entries, repRange: lowerBound...upperBound) else {
            throw DecodingError.dataCorruptedError(
                forKey: .entries,
                in: container,
                debugDescription:
                    "RPETable entries must be non-empty, finite, strictly ascending and within "
                    + "0 < fraction <= 1, with repRangeLowerBound >= 1."
            )
        }
        self = table
    }

    /// Writes ``entries`` then the two bounds of ``repRange``, in that order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(repRange.lowerBound, forKey: .repRangeLowerBound)
        try container.encode(repRange.upperBound, forKey: .repRangeUpperBound)
    }
}
