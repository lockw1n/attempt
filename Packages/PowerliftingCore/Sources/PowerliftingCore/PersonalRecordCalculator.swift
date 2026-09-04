/// N-rep maxes and the best estimated one-rep maximum for one exercise's logged sets (`TR-0.2.8`).
///
/// **An N-rep max is the heaviest completed working set performed for *at least* N reps.** A 5-rep
/// set at 100 kg therefore holds the 1RM through the 5RM, not only the 5RM. Reading it as "for
/// exactly N reps" is the subtle wrong answer, and it silently loses records.
///
/// **The collection is ordered, and the order is chronological.** Nothing here has a timestamp
/// (`NFR-0.2`), so *earlier* means *earlier in the collection supplied* — which is how a tie
/// between two equally heavy sets resolves. A caller handing over sets in any other order gets a
/// defensible answer to a different question. `FR-1.7.1`'s lookback window is applied the same way:
/// by choosing what goes in, not by anything this type knows.
///
/// **Nothing is cached** (`G-1.4`). Every call recomputes from the sets given, which is what lets
/// `FR-1.6.4` and `FR-1.7.3` recalculate history when the formula setting changes rather than only
/// new sets. `TR-0.3.9`'s `PersonalRecordCacheEntity` is the only cache there is, and it lives in
/// the persistence layer where a `computationVersion` can invalidate it (`G-1.5`).
///
/// **The e1RM half routes through ``E1RMCalculator``, deliberately, and that is load-bearing.**
/// Reaching a formula directly — `Epley().estimate(for:)` — bypasses every refusal `TR-0.2.5`
/// names, including the negative-weight one, and a personal record is exactly where that would
/// mislead: it ranks the *most*-assisted attempt highest. The N-rep max half does **not** inherit
/// that refusal, and must not; see ``PersonalRecords/bestE1RM``.
public struct PersonalRecordCalculator: Sendable {
    /// The estimator the e1RM record is read through — the sole entry point, never a bare formula.
    public let e1rm: E1RMCalculator

    /// Creates a calculator reading estimates through `e1rm`.
    public init(e1rm: E1RMCalculator) {
        self.e1rm = e1rm
    }

    /// Creates a calculator using the formula `id` names, or ``E1RMFormulaID/defaultFormula``.
    public init(_ id: E1RMFormulaID = .defaultFormula) {
        self.init(e1rm: E1RMCalculator(id))
    }

    /// The version of the rules below, which a `G-1.5` cache of these records stores alongside it.
    ///
    /// Bump it when a change here would produce a different record from identical sets — a
    /// different tie-break, a different definition of a working set. A *settings* change is not one
    /// of these: `TR-1.6` and `FR-1.6.4` make that a separate invalidation trigger, which is why
    /// the rep-max rules, reading no setting whatsoever, are the half that `TR-0.3.9` may cache.
    ///
    /// Always at least 1, so that a stored zero — what a defaulted column yields under `G-2.5` —
    /// can only mean no version was recorded.
    ///
    /// The persistence layer must not declare a version of its own: a copy there is one nobody
    /// bumps when this file changes.
    ///
    /// **It versions ``SchemeRecordCalculator``'s rules too, because they are one cached table.**
    /// `FR-16.2.1` makes the N-rep max the `sets == 1` row of the scheme table, so a second constant
    /// would version half a row; the number lives here because this is where `G-1.5`'s reader
    /// already looks.
    ///
    /// **2 since `TR-16.1`**: the cell key gained a set count and the row gained the load it beat, so
    /// identical sets produce a different row from the one version 1 wrote.
    public static let computationVersion = 2

    /// Every record `sets` holds.
    ///
    /// - Parameter sets: One exercise's sets, oldest first. Warmups and incomplete sets may be
    ///   included; they are excluded here rather than by the caller.
    public func records(in sets: [SetRecord]) -> PersonalRecords {
        let repMaxes = PersonalRecords.repRange.compactMap { reps in
            repMax(forReps: reps, in: sets).map { RepMax(reps: reps, record: $0) }
        }
        return PersonalRecords(repMaxes: repMaxes, bestE1RM: bestE1RM(in: sets))
    }

    /// The heaviest completed working set in `sets` performed for at least `reps` reps.
    ///
    /// A negative weight is a candidate like any other: an assisted pull-up genuinely is a lighter
    /// lift than an unassisted one, and `Comparable` already ranks −20 kg below −10 kg. The sign
    /// rule ``E1RMCalculator`` applies belongs to estimation, where more assistance would otherwise
    /// read as a heavier maximum; here it would delete real records.
    ///
    /// - Parameters:
    ///   - reps: The N, within ``PersonalRecords/repRange``.
    ///   - sets: One exercise's sets, oldest first.
    /// - Returns: `nil` when no set qualifies, or when `reps` is outside ``PersonalRecords/repRange``.
    public func repMax(forReps reps: Int, in sets: [SetRecord]) -> PersonalRecord? {
        guard PersonalRecords.repRange.contains(reps) else { return nil }
        return best(in: sets) { set in
            set.isWarmup || !set.isCompleted || set.reps < reps ? nil : set.weight
        }
    }

    /// The heaviest estimate any set in `sets` produces under this calculator's formula.
    ///
    /// Where two sets estimate identically the earlier one holds the record, as for a rep max.
    ///
    /// - Parameter sets: One exercise's sets, oldest first.
    /// - Returns: `nil` when no set yielded an estimate, whether refused here or declined by the
    ///   formula — see ``PersonalRecords/bestE1RM``, which the `.rpeBased` case surprises.
    public func bestE1RM(in sets: [SetRecord]) -> PersonalRecord? {
        best(in: sets) { e1rm.estimate(for: $0) }
    }

    /// The largest weight `candidate` yields over `sets`, earliest offset winning a tie.
    ///
    /// The comparison is strict, which *is* the tie-break: an equally heavy set later in the
    /// collection never displaces the one already held. `FR-1.6.3` badges a PR at the moment it is
    /// logged, so repeating a record is not setting one.
    private func best(in sets: [SetRecord], _ candidate: (SetRecord) -> Weight?) -> PersonalRecord? {
        var best: PersonalRecord?
        for (offset, set) in sets.enumerated() {
            guard let weight = candidate(set) else { continue }
            if let held = best, weight <= held.weight { continue }
            best = PersonalRecord(weight: weight, setOffset: offset)
        }
        return best
    }
}
