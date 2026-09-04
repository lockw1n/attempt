/// The `(reps, sets)` pair a personal record is keyed by (`FR-16.2.1`).
///
/// **The N-rep max is the `sets == 1` row of this table**, not a separate kind of record. `4 × 4` at
/// 100 kg and `4 × 1` at 100 kg are different cells, and `FR-1.6.1`'s ten rep maxes are one column
/// of the sixty cells ``SchemeRecordCalculator`` fills.
///
/// **``sets`` is how many consecutive sets were required, not how many were performed.** A run of
/// five sets holds the two-set scheme as surely as the five-set one — see
/// ``SchemeRecordCalculator``'s dominance rule.
public struct RecordScheme: Sendable, Hashable, Comparable {
    /// The N: at least this many repetitions, per set.
    public let reps: Int

    /// How many consecutive sets at that rep count the scheme asks for.
    public let sets: Int

    /// Creates a scheme. Neither bound is validated; see ``SchemeRecordCalculator`` for the ranges
    /// a computed record falls in.
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
    /// **Largest `reps × sets`, with ``<`` breaking a tie.** For the cells one run holds that is the
    /// same answer the plain order gives, the run's own corner dominating every other cell it set in
    /// both dimensions; the product is what the requirement asks for and what stays right if a
    /// caller ever hands this cells that are not one run's — `10 × 1` orders above `5 × 3` and is
    /// the smaller performance.
    ///
    /// - Parameter schemes: The cells, in any order.
    /// - Returns: The maximal one, or `nil` where there are none.
    public static func maximal(of schemes: some Sequence<Self>) -> Self? {
        schemes.max { lhs, rhs in
            (lhs.reps * lhs.sets, lhs) < (rhs.reps * rhs.sets, rhs)
        }
    }
}

/// A run of consecutive equal working sets, as the record rules see one (`FR-16.1.1`).
///
/// **What a caller has already established, not what this module can compute.** Consecutiveness is
/// a property of the order sets were logged in, and a warmup or a failed set standing between two
/// otherwise equal sets ends the run — neither of which this module can see, since it has no
/// identity and no ordering beyond the collection it is handed. The caller groups; this counts.
public struct SetRun: Sendable, Hashable {
    /// The load every set in the run carried. Signed: assisted work runs negative.
    public let weight: Weight

    /// The repetitions every set in the run carried.
    public let reps: Int

    /// How many sets it holds — the `× 4`. At least 1.
    public let count: Int

    /// The position of the run's **first** set in the collection the caller supplied.
    ///
    /// The first rather than the last, and that choice is what keeps one run one record: the set
    /// that *completed* a scheme differs per cell — two sets complete the two-set scheme, five the
    /// five-set one — so a per-cell answer would give one run several identities and split it into
    /// several events wherever records are listed as events.
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

    /// The position of the record-holding run's first set — see ``SetRun/setOffset``.
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

/// `FR-16.2.2`'s dominance rule: what a table of scheme records is, given the runs behind it.
///
/// **A run `W × R × S` establishes `W` at every cell with reps ≤ R and sets ≤ S.** That is
/// `FR-1.6.1`'s "at least N reps" extended to a second dimension: five sets of five at 100 kg is a
/// three-set-of-two performance too, and refusing to say so would leave a lifter's `2 × 3` empty
/// while their `5 × 5` stands at the same load.
///
/// **The collection is ordered, and the order is chronological**, on
/// ``PersonalRecordCalculator``'s rule — this module has no `Date`, so *earlier* means *earlier in
/// the collection supplied*. It is what resolves a tie, and it is also what makes
/// ``SchemeRecord/previousWeight`` computable in the one pass: a cell's value at the moment a
/// heavier run reaches it **is** the load that run beat.
///
/// **Nothing is cached** (`G-1.4`), as for every calculator here.
public struct SchemeRecordCalculator: Sendable {
    /// How many sets a scheme is computed up to (`FR-16.2.2`).
    ///
    /// **Six, and the bound is a product decision rather than an arithmetic one.** The table is
    /// `repRange × setRange` cells per exercise and every one of them is a stored row, so the
    /// second dimension is what multiplies the cache; a run longer than six sets is not a scheme
    /// anybody trains against, and it still sets every cell up to six.
    public static let setRange: ClosedRange<Int> = 1...6

    /// Creates a calculator. It reads no setting — which is what keeps `TR-0.3.9`'s cache legal
    /// under `G-1.5`, one version being a complete statement of what produced a row.
    public init() {}

    /// Every scheme record `runs` holds, ascending by ``SchemeRecord/scheme``.
    ///
    /// A run reaching past either bound **clamps** rather than being refused: eight sets of twelve
    /// is a record at `10 × 6`, and the cells above the bounds are not cells.
    ///
    /// - Parameter runs: One exercise's runs of consecutive equal completed working sets, oldest
    ///   first. Warmups, failures and the runs they interrupt are the caller's to exclude — see
    ///   ``SetRun``.
    /// - Returns: The records, one per cell any run reached.
    public func records(in runs: [SetRun]) -> [SchemeRecord] {
        var held: [RecordScheme: SchemeRecord] = [:]
        for run in runs {
            let reps = min(run.reps, PersonalRecords.repRange.upperBound)
            let sets = min(run.count, Self.setRange.upperBound)
            guard reps >= PersonalRecords.repRange.lowerBound, sets >= Self.setRange.lowerBound
            else { continue }
            for repCount in PersonalRecords.repRange.lowerBound...reps {
                for setCount in Self.setRange.lowerBound...sets {
                    let scheme = RecordScheme(reps: repCount, sets: setCount)
                    // Strict, which *is* the tie-break: repeating a record is not setting one, so an
                    // equal load later leaves the earlier run holding the cell — and leaves the
                    // beaten load untouched, which is what stops a repeat reading as an improvement
                    // over itself.
                    if let standing = held[scheme], run.weight <= standing.weight { continue }
                    held[scheme] = SchemeRecord(
                        scheme: scheme,
                        weight: run.weight,
                        setOffset: run.setOffset,
                        previousWeight: held[scheme]?.weight)
                }
            }
        }
        return held.values.sorted { $0.scheme < $1.scheme }
    }
}
