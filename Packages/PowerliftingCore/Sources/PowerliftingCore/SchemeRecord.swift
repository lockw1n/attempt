/// The `(reps, sets)` pair a personal record is keyed by (`FR-16.2.1`).
///
/// **The N-rep max is the `sets == 1` row of this table**, not a separate kind of record. `4 × 4` at
/// 100 kg and `4 × 1` at 100 kg are different cells, and `FR-1.6.1`'s ten rep maxes are one column
/// of the sixty cells ``SchemeRecordCalculator`` fills.
///
/// **``reps`` and ``sets`` are what was performed, exactly** (`FR-17.2.1`). A run of five sets of
/// five is the `5 × 5` cell and no other: it is not evidence about `3 × 2`, because more could have
/// been lifted for `3 × 2`.
///
/// **Both fields are unguarded here and bounded where one is computed.** A scheme built by hand
/// takes any `Int` in either — repetitions per set, and consecutive sets at that count. Every
/// scheme this module *computes* lies within ``PersonalRecords/repRange`` repetitions and
/// ``SchemeRecordCalculator/setRange`` sets, which is where ``SchemeRecordCalculator/cell(for:)``
/// refuses a run outside them rather than clamping it (`NFR-0.3`, `FR-17.2.1`).
public struct RecordScheme: Sendable, Hashable, Comparable {
    /// The N: exactly this many repetitions, per set.
    public let reps: Int

    /// How many consecutive sets at that rep count were performed.
    public let sets: Int

    /// Creates a scheme. Neither bound is validated — see the type's own note.
    public init(reps: Int, sets: Int) {
        self.reps = reps
        self.sets = sets
    }

    /// Orders schemes by reps and then by sets — the order a computed table is returned in.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.reps, lhs.sets) < (rhs.reps, rhs.sets)
    }

    /// The maximal scheme among `schemes` — the one a badge names (`FR-16.2.4`) — or `nil` for
    /// none.
    ///
    /// **Largest `reps × sets`, with the scheme order (`<`) breaking a tie.** Since `FR-17.2.1` a
    /// run holds exactly one cell, so every caller here hands this one scheme or none and the choice
    /// is trivial — it is kept because the rule is what stays right if a caller ever hands this
    /// cells that are not one run's: `10 × 1` orders above `5 × 3` and is the smaller performance.
    ///
    /// - Parameter schemes: The cells, in any order.
    /// - Returns: The maximal one, or `nil` where there are none.
    public static func maximal(of schemes: some Sequence<Self>) -> Self? {
        schemes.max { lhs, rhs in
            (lhs.reps * lhs.sets, lhs) < (rhs.reps * rhs.sets, rhs)
        }
    }
}

/// A run of consecutive working sets at one load and one repetition count — the `100 kg × 5 × 4`
/// a lifter writes down (`FR-16.1.1`).
///
/// **What a caller has already established, not what this module can compute.** Consecutiveness is
/// a property of the order sets were logged in, and a warmup or a failed set standing between two
/// otherwise equal sets ends the run — neither of which this module can see, since it has no
/// identity and no ordering beyond the collection it is handed. The caller groups; this counts.
public struct SetRun: Sendable, Hashable {
    /// The load every set in the run carried. Signed: assisted work runs negative.
    public let weight: Weight

    /// The repetitions every set in the run carried.
    ///
    /// Zero upwards, on ``SetRecord/reps``' rule: a failed set records the reps it reached, which
    /// can be none. A run outside ``PersonalRecords/repRange`` sets no record at either end — see
    /// ``SchemeRecordCalculator/cell(for:)``, where that rule lives.
    public let reps: Int

    /// How many sets it holds — the `× 4`.
    ///
    /// At least 1, and it counts *sets* where ``reps`` counts repetitions: a run of five sets of
    /// five has 5 in both, which is the one place the two are easy to read for each other.
    public let count: Int

    /// The position of the run's **first** set in the collection the caller supplied.
    ///
    /// Zero-based, and a valid index into that collection where the caller built this from one; a
    /// hand-built run is not checked, as ``PersonalRecord/setOffset`` is not.
    ///
    /// The first rather than the last, and that choice is what makes a run's identity readable
    /// before the run is over: the set that *completed* it is not known until the run ends, so a
    /// badge keyed on the last set would move down the card as the lifter logged, and a feed keyed
    /// on it would reorder a session's events after the fact.
    public let setOffset: Int

    /// Creates a run.
    public init(weight: Weight, reps: Int, count: Int, setOffset: Int) {
        self.weight = weight
        self.reps = reps
        self.count = count
        self.setOffset = setOffset
    }
}

/// One scheme's record: the load, where it came from, and what it beat (`FR-16.2.1`, `FR-16.2.3`).
public struct SchemeRecord: Sendable, Hashable {
    /// The cell this is the record for.
    public let scheme: RecordScheme

    /// The record load.
    public let weight: Weight

    /// The position of the record-holding run's first set — zero-based, and see
    /// ``SetRun/setOffset`` for what it indexes into.
    public let setOffset: Int

    /// The load this record beat at this scheme, or `nil` where it is a baseline: the first time
    /// the scheme was ever performed for the exercise (`FR-16.2.3`).
    ///
    /// **A baseline and a first improvement are different events**, which is the whole reason this
    /// is optional rather than zero — `Weight` is signed, so a beaten load of zero is a real one.
    public let previousWeight: Weight?

    /// Creates a scheme record.
    public init(scheme: RecordScheme, weight: Weight, setOffset: Int, previousWeight: Weight?) {
        self.scheme = scheme
        self.weight = weight
        self.setOffset = setOffset
        self.previousWeight = previousWeight
    }
}

/// `FR-17.2.1`'s rule: what a table of scheme records is, given the runs behind it.
///
/// **A run `W × R × S` establishes `W` at the `(R, S)` cell and at no other.** A load lifted for
/// `5 × 5` is not a `3 × 3` record — more could have been lifted for `3 × 3` — so a cell no run
/// reached reads as never performed rather than as an implied record. `FR-16.2.2`'s dominance
/// reading is withdrawn, and `FR-1.6.1`'s "at least N reps" with it.
///
/// **The collection is ordered, and the order is chronological**, on
/// ``PersonalRecordCalculator``'s rule — this module has no `Date`, so *earlier* means *earlier in
/// the collection supplied*. It is what resolves a tie, and it is also what makes
/// ``SchemeRecord/previousWeight`` computable in the one pass: a cell's value at the moment a
/// heavier run reaches it **is** the load that run beat.
///
/// **Nothing is cached** (`G-1.4`), as for every calculator here.
public struct SchemeRecordCalculator: Sendable {
    /// How many sets a scheme is computed up to (`FR-17.2.1`).
    ///
    /// **Six, and the bound is a product decision rather than an arithmetic one.** The table is
    /// `repRange × setRange` cells per exercise and every one of them is a stored row, so the
    /// second dimension is what multiplies the cache; a run longer than six sets is not a scheme
    /// anybody trains against, and it sets no record rather than recording at six — see
    /// ``cell(for:)``.
    public static let setRange: ClosedRange<Int> = 1...6

    /// Creates a calculator. It reads no setting — which is what keeps `TR-0.3.9`'s cache legal
    /// under `G-1.5`, one version being a complete statement of what produced a row.
    public init() {}

    /// The cell `run` was performed at — its own scheme — or `nil` where that is not a cell.
    ///
    /// **The one place a run is turned into a cell**, so the table's bounds are stated once, and
    /// since `FR-17.2.1` it is the only cell the run reaches.
    ///
    /// **A run outside either bound reaches nothing, and it is refused rather than clamped**
    /// (`FR-17.2.1`, `FR-1.6.1`). Clamping was right under the withdrawn dominance rule, where a
    /// run stood at every cell at or below its corner and the corner was only the largest of them;
    /// with one cell per run it is the one remaining way a load is claimed at a scheme nobody
    /// performed. Twelve reps is not a set of ten — more could have been lifted for ten — and eight
    /// sets is not six, on the same argument in the other dimension. So a set of eleven sets no
    /// record, exactly as ``PersonalRecordCalculator/repMax(forReps:in:)`` already refuses it, and
    /// the two computations of `FR-1.6.1` agree at every N. A run below the rep floor — a set of
    /// none, which a failed set records — reaches nothing for the same reason.
    ///
    /// - Parameter run: The run.
    /// - Returns: The cell it was performed at, or `nil`.
    public static func cell(for run: SetRun) -> RecordScheme? {
        guard PersonalRecords.repRange.contains(run.reps), Self.setRange.contains(run.count)
        else { return nil }
        return RecordScheme(reps: run.reps, sets: run.count)
    }

    /// Every scheme record `runs` holds, ascending by ``SchemeRecord/scheme``.
    ///
    /// **One cell per run** (`FR-17.2.1`), which is ``cell(for:)``'s. A run outside either bound
    /// reaches no cell at all, and that rule lives there too.
    ///
    /// - Parameter runs: One exercise's runs of consecutive equal completed working sets, oldest
    ///   first. Warmups, failures and the runs they interrupt are the caller's to exclude — see
    ///   ``SetRun``.
    /// - Returns: The records, one per cell some run was performed at.
    public func records(in runs: [SetRun]) -> [SchemeRecord] {
        var held: [RecordScheme: SchemeRecord] = [:]
        for run in runs {
            guard let scheme = Self.cell(for: run) else { continue }
            // Strict, which *is* the tie-break: repeating a record is not setting one, so an equal
            // load later leaves the earlier run holding the cell — and leaves the beaten load
            // untouched, which is what stops a repeat reading as an improvement over itself.
            if let standing = held[scheme], run.weight <= standing.weight { continue }
            held[scheme] = SchemeRecord(
                scheme: scheme,
                weight: run.weight,
                setOffset: run.setOffset,
                previousWeight: held[scheme]?.weight)
        }
        return held.values.sorted { $0.scheme < $1.scheme }
    }
}
