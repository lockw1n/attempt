/// A one-rep maximum read off an RPE/RIR chart (`TR-0.2.4`).
///
/// The other five equations of `TR-0.2.4` predict from a rep count alone. This one asks how hard
/// the set felt, so it conforms to ``E1RMFormula`` directly rather than ``RepOnlyE1RMFormula``:
/// there is no `multiplier(forReps:)` to give, and the rep-range guard that protocol's extension
/// supplies is applied here instead.
///
/// **``SetRecord/rpe`` wins when both effort fields are present, and neither is rewritten.** The
/// two encode one scale twice (`rir = 10 - rpe`) but are stored independently, so a logged set may
/// honestly carry a contradictory pair and `G-1.6` forbids correcting it. RPE is preferred for
/// being the finer of the two — it admits half points and finer, where RIR is whole reps — and for
/// being the scale the chart is drawn in. A set carrying neither estimates as `nil`; there is
/// nothing to look up.
///
/// ``validRepRange`` and every percentage come from ``table``, so replacing the chart is
/// constructing a different value.
public struct RPEBased: E1RMFormula {
    /// See ``E1RMFormula/id``.
    public let id = E1RMFormulaID.rpeBased

    /// The chart this instance reads.
    public let table: RPETable

    /// The rep counts ``table`` covers.
    ///
    /// Read from the chart rather than shared with the closed-form five: those agree on `1...10` as
    /// a finding about where five equations stop agreeing, which is not an argument about a chart.
    public var validRepRange: ClosedRange<Int> { table.repRange }

    /// Creates a formula reading `table`, or the conventional chart if none is given.
    ///
    /// - Parameter table: The chart to read. Defaults to ``RPETable/standard``, whose doc comment
    ///   carries the provenance caveat that applies to every estimate this type produces by
    ///   default.
    public init(table: RPETable = .standard) {
        self.table = table
    }

    /// The estimated one-rep maximum for `set`, or `nil` if the chart has no cell for it.
    ///
    /// - Parameter set: The logged set. ``SetRecord/isWarmup`` and ``SetRecord/isCompleted`` are
    ///   deliberately not consulted — see ``E1RMFormula``.
    /// - Returns: The estimate in whole grams, or `nil` when ``SetRecord/reps`` falls outside
    ///   ``validRepRange``, when the set records neither ``SetRecord/rpe`` nor ``SetRecord/rir``,
    ///   when the effort falls off either end of ``table``, or when the result will not fit in a
    ///   `Weight`. Those are four distinct refusals sharing one answer, which is why each has its
    ///   own test.
    public func estimate(for set: SetRecord) -> Weight? {
        guard validRepRange.contains(set.reps),
            let reserve = Self.repsInReserve(for: set),
            let fraction = table.fractionOfMax(atRepsToFailure: Double(set.reps) + reserve)
        else {
            return nil
        }
        return set.weight.scaled(by: 1 / fraction)
    }

    /// Reps left in reserve, from whichever effort field the set carries — see the type's note on
    /// precedence. `nil` when it carries neither.
    static func repsInReserve(for set: SetRecord) -> Double? {
        if let rpe = set.rpe { return SetRecord.rpeRange.upperBound - rpe }
        if let rir = set.rir { return Double(rir) }
        return nil
    }
}
