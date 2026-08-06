/// The stable name of an e1RM formula (`TR-0.2.4`).
///
/// **A storage contract, not a debugging convenience.** `TR-0.3.8` puts "e1RM formula" on
/// `UserSettingsEntity`, so a name has to survive a relaunch and reach another device. Renaming a
/// case, or changing a raw value, is a migration.
///
/// **An unrecognised name throws** — the vocabulary is closed by what code exists, since a formula
/// is an implementation and a name with nothing behind it cannot be computed with or meaningfully
/// preserved. Callers must not let that throw cost the whole settings record: a row whose formula
/// name is unreadable falls back to a default formula.
///
/// A case exists only where an implementation does. That is what makes the throw above defensible,
/// and it is a rule about this type rather than an observation about its current contents.
public enum E1RMFormulaID: String, Sendable, Hashable, Codable, CaseIterable {
    /// Epley (1985) — see ``Epley``.
    case epley

    /// Brzycki (1993) — see ``Brzycki``.
    case brzycki

    /// Lombardi (1989) — see ``Lombardi``.
    case lombardi

    /// O'Conner, Simmons and O'Shea (1989) — see ``OConner``.
    ///
    /// Spelled all-lowercase rather than letting Swift derive `"oConner"`, so the persisted string
    /// does not encode a Swift naming convention.
    case oConner = "oconner"

    /// Wathan (1994) — see ``Wathan``.
    case wathan

    /// An RPE/RIR chart rather than a published equation — see ``RPEBased``.
    ///
    /// Spelled all-lowercase for the same reason ``oConner`` is: the persisted string is not the
    /// place to record how Swift capitalises identifiers.
    case rpeBased = "rpebased"
}

extension E1RMFormulaID {
    /// The rep range the five closed-form equations are valid over — 1 through 10.
    ///
    /// The lower bound is arithmetic: a zero-rep set is legal (`FR-1.2.5`) and carries no
    /// information about a maximum, and Lombardi's `reps^0.10` is zero there, so the estimate for a
    /// failed set would be "no weight at all". The upper bound is where the five stop agreeing —
    /// asserted in `E1RMRepRangeTests`, which carries the measured spread. `TR-0.2.8` computes
    /// N-rep maxes over the same 1…10.
    ///
    /// **The range is a per-conformance property, not a constant of the protocol.** These five
    /// agreeing is a finding about them, not a limit on the sixth: ``RPEBased`` takes its range
    /// from its chart, and does not read this.
    public static let tabulatedRepRange: ClosedRange<Int> = 1...10
}
