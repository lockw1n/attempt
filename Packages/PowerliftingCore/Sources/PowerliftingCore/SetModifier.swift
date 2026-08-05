/// A qualifier applied to a logged set — the nine `FR-1.2.8` names, as spelled on the wire.
///
/// The *built-in* list, not the whole list: `FR-1.2.8` calls the modifier set **configurable**, so
/// a value outside these nine is ordinary rather than corruption. That is why the persistable form
/// is ``SetModifier``, an ``OpenVocabulary`` around this enum, and not this enum itself.
///
/// **Deliberately not `Codable`.** Encoding a term directly would give a type that throws on an
/// unrecognised spelling — the exact behaviour this area exists to avoid. Adding `Codable` here
/// would reintroduce that trap as a convenience.
public enum SetModifierTerm: String, Sendable, Hashable, CaseIterable {
    /// A lifting belt.
    case belt

    /// Knee sleeves.
    case sleeves

    /// Knee or wrist wraps. Kept apart from ``sleeves`` because the two are not equivalent
    /// support and a lifter's history mixes them.
    case wraps

    /// Lifting straps — a pulling aid, so a strapped set is not comparable to an unstrapped one.
    case straps

    /// A deliberate pause at some point in the range of motion — a competition-command bench,
    /// a paused squat.
    case paused

    /// A prescribed tempo. Which tempo is not modelled here; `TR-0.2.3` gives the set a flat list
    /// of modifiers and nothing carries a parameter.
    case tempo

    /// Reps taken touch-and-go rather than reset — the deadlift counterpart to ``paused``.
    case touchAndGo

    /// Performed from a deficit — standing on a platform.
    case deficit

    /// Performed to a board or block, shortening the range of motion.
    case board
}

/// A set modifier as logged and persisted: one of ``SetModifierTerm``'s nine, or any other
/// spelling, kept verbatim (`FR-1.2.8`, `TR-0.2.3`).
///
/// Write `SetModifier(.belt)` for a built-in term and `SetModifier(rawValue: "chains")` for
/// anything else; read ``OpenVocabulary/known`` to get back a `SetModifierTerm?`. Encodes as the
/// bare string `"belt"`.
///
/// An unrecognised spelling is **preserved, never degraded** — unlike ``Movement`` or
/// ``Equipment``, a set modifier is the user's own logged data and nothing re-supplies it.
public typealias SetModifier = OpenVocabulary<SetModifierTerm>
