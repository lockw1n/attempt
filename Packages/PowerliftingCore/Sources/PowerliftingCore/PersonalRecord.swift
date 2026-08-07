/// A personal record: a weight, and where the set holding it sits in the collection it came from
/// (`TR-0.2.8`).
///
/// **``setOffset`` is an offset, not an identity.** This package has no `UUID` and no `Date`
/// (`NFR-0.2`), so a record cannot name the set it came from or say when it happened. The caller
/// supplied the collection and maps the offset back to whatever identity it holds — which is what
/// `TR-0.3.9`'s `sourceSetID` and `achievedAt` are filled from, and what `FR-1.6.2`'s link to the
/// source set resolves through.
public struct PersonalRecord: Sendable, Hashable {
    /// The record weight.
    ///
    /// For an N-rep max this is the load logged on the set, so it is a weight somebody lifted. For
    /// ``PersonalRecords/bestE1RM`` it is an estimate, which is not.
    public let weight: Weight

    /// The position of the record-holding set in the collection this was computed from.
    public let setOffset: Int

    /// Creates a record.
    public init(weight: Weight, setOffset: Int) {
        self.weight = weight
        self.setOffset = setOffset
    }
}

/// An N-rep max: the heaviest completed working set performed for **at least** ``reps`` reps
/// (`TR-0.2.8`, `FR-1.6.1`).
public struct RepMax: Sendable, Hashable {
    /// The N this is the record for — not the reps the set was performed for, which may be more.
    ///
    /// A 5-rep set is a candidate for every N from 1 to 5, so one set can hold five records at the
    /// same weight. That is the definition, not a rounding of it.
    ///
    /// In a value ``PersonalRecordCalculator`` produced this falls within
    /// ``PersonalRecords/repRange``. That is the calculator's guarantee and not this type's — the
    /// initialiser takes any `Int`, because nothing in the module consumes a hand-built record and a
    /// failable initialiser here would buy a boundary no caller crosses.
    public let reps: Int

    /// The record itself.
    public let record: PersonalRecord

    /// Creates an N-rep max.
    public init(reps: Int, record: PersonalRecord) {
        self.reps = reps
        self.record = record
    }
}

/// Every personal record a collection of sets holds (`TR-0.2.8`).
///
/// **Scoped to one exercise, by the caller.** Nothing here carries an exercise identity, so the
/// collection this was computed from must already be one exercise's. That is what makes the
/// per-implement weight convention safe — see ``SetRecord/weight``: a 40 kg single-arm row is only
/// ever ranked against other single-arm rows, because there is no way to hand this type anything
/// else.
public struct PersonalRecords: Sendable, Hashable {
    /// The rep counts an N-rep max is computed for — 1 through 10, per `TR-0.2.8`.
    public static let repRange: ClosedRange<Int> = 1...10

    /// The N-rep maxes.
    ///
    /// In a value ``PersonalRecordCalculator/records(in:)`` produced these are ascending by
    /// ``RepMax/reps``, and an N no set reached is **absent** rather than present at a weight of
    /// zero — `Weight` is signed, so zero is a real load with assisted work below it, and "no
    /// record" is a different answer from "a record of zero". Ordering is the calculator's
    /// guarantee rather than this type's; see ``RepMax/reps`` for why it is not enforced here.
    public let repMaxes: [RepMax]

    /// The heaviest estimated one-rep maximum any set produced, or `nil` when none did.
    ///
    /// `nil` when no set yielded an estimate — each one either refused by ``E1RMCalculator`` (a
    /// warmup, incomplete, outside the formula's rep range, or assisted) **or declined by the
    /// formula itself**. The second is easy to overlook and is the usual outcome under
    /// ``RPEBased``, which has nothing to say about a set recording neither an RPE nor an RIR.
    ///
    /// Either way the log keeps its N-rep maxes: assisted work ranks perfectly well as a logged
    /// load, and an unrated set is still a heaviest-for-N candidate.
    public let bestE1RM: PersonalRecord?

    /// Creates a set of records.
    public init(repMaxes: [RepMax], bestE1RM: PersonalRecord?) {
        self.repMaxes = repMaxes
        self.bestE1RM = bestE1RM
    }

    /// The N-rep max for `reps`, or `nil` when no set reached that many reps.
    ///
    /// A lookup, not a guard: it finds whatever ``repMaxes`` holds. In a value
    /// ``PersonalRecordCalculator/records(in:)`` produced nothing outside ``repRange`` is stored, so
    /// asking outside it finds nothing — but the range is enforced on
    /// ``PersonalRecordCalculator/repMax(forReps:in:)``, not here.
    ///
    /// - Parameter reps: The N.
    /// - Returns: The record, or `nil` when ``repMaxes`` holds none for that rep count.
    public func repMax(forReps reps: Int) -> PersonalRecord? {
        repMaxes.first { $0.reps == reps }?.record
    }
}
