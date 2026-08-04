/// The stable name of an e1RM formula (`TR-0.2.4`).
///
/// **This is a storage contract, not a debugging convenience.** `TR-0.3.8` puts "e1RM formula" on
/// `UserSettingsEntity`, so something has to name a formula in a way that survives a relaunch and
/// reaches another device. That name is defined here rather than in the storage layer, so there is
/// one spelling of it instead of one per persistence mechanism. Renaming a case, or changing a raw
/// value, is a migration.
///
/// **An unrecognised name throws**, like ``RoundingStrategy`` and unlike `Movement`, `Equipment`
/// and `SetModifier`. The module's rule for unknown enum values turns on two questions — is the
/// vocabulary open, and is there an upstream copy — and both answers point the same way here. The
/// vocabulary is closed by what code exists: a formula is an implementation, so a name with no
/// implementation behind it cannot be computed with, degraded into something computable, or
/// meaningfully preserved. There is nothing a seed re-import (T-0.52) could restore.
///
/// **That throw comes with an obligation on T-0.32**, recorded in that task's file: a settings row
/// whose formula name is unreadable must fall back to a default formula, not fail to decode. This
/// enum refuses to invent a formula; it does not follow that the whole settings record should be
/// lost over one field. The same obligation `Laterality`'s throw placed on T-0.31 and T-0.42.
///
/// `TR-0.2.4` names a sixth formula, `RPEBased`, which T-0.15 builds. Its case is deliberately
/// absent until the implementation exists — a name that resolves to nothing is exactly what the
/// paragraph above says this type must not contain. Adding it later is additive and safe: nothing
/// has persisted a formula name yet.
public enum E1RMFormulaID: String, Sendable, Hashable, Codable, CaseIterable {
    /// Epley (1985) — see ``Epley``.
    case epley

    /// Brzycki (1993) — see ``Brzycki``.
    case brzycki

    /// Lombardi (1989) — see ``Lombardi``.
    case lombardi

    /// O'Conner, Simmons and O'Shea (1989) — see ``OConner``.
    ///
    /// The raw value is spelled all-lowercase rather than letting Swift derive `"oConner"` from
    /// the case name, so that the persisted string does not encode a Swift naming convention. The
    /// surname follows `TR-0.2.4`'s spelling.
    case oConner = "oconner"

    /// Wathan (1994) — see ``Wathan``.
    case wathan
}

extension E1RMFormulaID {
    /// The rep range every formula in this family is valid over — 1 through 10.
    ///
    /// **This is one number with three independent reasons, and it is a decision rather than a
    /// citation.** T-0.14's brief expected the five ranges to differ; measured, they do not, and
    /// inventing per-formula ceilings would have been a fabricated reference value in a task whose
    /// whole point is not fabricating those.
    ///
    /// *The lower bound is arithmetic.* A set of zero reps is a legal ``SetRecord`` (`FR-1.2.5` —
    /// a failed set records what was achieved) and carries no information about a one-rep maximum.
    /// It is not merely uninformative either: Lombardi's `reps^0.10` evaluates to zero there, so
    /// the estimate for a failed set would be "no weight at all".
    ///
    /// *The upper bound is where the five stop agreeing.* Measured multipliers, for a lift of any
    /// size:
    ///
    /// | reps | Epley | Brzycki | Lombardi | O'Conner | Wathan | spread |
    /// |---|---|---|---|---|---|---|
    /// | 10 | 1.333 | 1.333 | 1.259 | 1.250 | 1.347 | 0.097 |
    /// | 15 | 1.500 | 1.636 | 1.311 | 1.375 | 1.509 | 0.325 |
    /// | 20 | 1.667 | 2.118 | 1.349 | 1.500 | 1.645 | 0.769 |
    /// | 30 | 2.000 | 5.143 | 1.405 | 1.750 | 1.836 | 3.738 |
    ///
    /// Five equations that agree to within 10% and then diverge to 370% are not five measurements
    /// of the same quantity past the point they part company. Ten reps is also where each was
    /// published as a percentage table.
    ///
    /// *And it is the horizon the rest of the module already works to.* `TR-0.2.8` computes N-rep
    /// maxes for N = 1…10.
    ///
    /// **The range is a per-conformance property, not a constant of the protocol**, so this
    /// staying uniform is a finding about these five rather than a limit on the sixth: T-0.15's
    /// `RPEBased` is keyed by RPE, not by reps, and is free to declare something else.
    public static let tabulatedRepRange: ClosedRange<Int> = 1...10
}
