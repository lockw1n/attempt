/// A value drawn from a vocabulary that is expected to grow, kept as the raw spelling so that a
/// term this version does not recognise survives a round trip unchanged.
///
/// > No `TR-0.2.x` defines this type — logged as gap §8 of the Phase 0 coverage matrix. T-0.12
/// > builds it because `FR-1.2.8` makes the set-modifier list **configurable**, which means values
/// > outside the built-in nine exist by design, and because T-0.20's notes asked for the
/// > preserved-unknown shape as a reusable value type rather than one welded into `Prescription`.
///
/// **The module answers "what do I do with an unrecognised raw value?" four different ways, and
/// this type is one of them.** Two independent questions decide it:
///
/// 1. *Throw, or tolerate?* Tolerate an open-ended vocabulary; throw where the vocabulary is
///    closed by the fact it describes. ``Laterality`` and ``RoundingStrategy`` throw.
/// 2. *If tolerating — degrade, or preserve?* Preserve when the value is the user's own data with
///    no authoritative copy anywhere else. Degrade only when something re-supplies it:
///    ``Movement``, ``Equipment`` and ``BarType`` degrade to their `other` case because a seed
///    re-import restores them (T-0.52).
///
/// This type is the *tolerate + preserve* answer. Nothing re-supplies a set modifier the user
/// logged, so dropping "wraps" because it arrived from a newer version destroys the only copy.
///
/// **It is canonical by construction: the raw spelling is the only stored property.** There is no
/// `known`/`unknown` pair of cases, and that is deliberate rather than a simplification. An enum
/// with two cases admits `.unknown("belt")` alongside `.known(.belt)` — two values that compare
/// unequal, hash differently and encode identically, so encoding would not be injective and a
/// duplicate check would miss a real duplicate. Storing the string removes the second
/// representation instead of documenting it away. ``known`` recovers the term when there is one.
///
/// **One residual case where equality and the bytes still diverge, in the other direction.**
/// Equality is `String`'s, which is canonical equivalence, so a precomposed `é` and a decomposed
/// one are the *same* value here while their UTF-8 differs (measured, T-0.12). Two values that
/// compare equal can therefore encode to different bytes, and a deduplicating caller keeps
/// whichever spelling it saw first. Round-tripping is unaffected — whatever string is stored comes
/// back exactly — and every built-in term is ASCII, so this is reachable only through a
/// user-configured modifier (`FR-1.2.8`) in Phase 1. Accepted for Phase 0 rather than fixed:
/// byte-exact equality would mean comparing UTF-8 views, which is a surprising contract for a type
/// that exposes a `String`, and it would change semantics for T-0.20 and T-0.31 with no
/// requirement asking for it.
///
/// **What it does not solve.** It preserves a *term*, not a payload. A future `Prescription` case
/// (T-0.20, `NFR-2.3`) carries associated values, and keeping only its discriminator would still
/// lose the numbers beside it. This type is the right shape for the tag; T-0.20 has to decide
/// separately how to hold the rest.
///
/// - Parameter Term: The vocabulary this version knows, as a `String`-backed enum. It is never
///   stored — only consulted by ``known`` — so equality, hashing and the wire format depend on
///   ``rawValue`` alone.
public struct OpenVocabulary<Term>: Sendable, Hashable, Codable, CustomStringConvertible
where Term: RawRepresentable, Term.RawValue == String {
    /// The persisted spelling, exactly as it was written or decoded.
    ///
    /// Any `String` is accepted, including one this version has never seen and including the
    /// empty string. Validating the spelling is the caller's business — this type's whole job is
    /// to be the place where an unvalidatable value can survive.
    public let rawValue: String

    /// Wraps a raw spelling, recognised or not.
    ///
    /// - Parameter rawValue: The persisted spelling. Not normalised in any way: case, spacing and
    ///   the empty string all round-trip verbatim, because normalising here would silently rewrite
    ///   a value the app cannot interpret and `G-1.6` forbids modifying logged data.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Wraps a term this version knows about — `SetModifier(.belt)`.
    ///
    /// - Parameter term: The recognised term. Its raw value becomes ``rawValue``.
    public init(_ term: Term) {
        self.rawValue = term.rawValue
    }

    /// The recognised term, or `nil` when ``rawValue`` belongs to a vocabulary this version does
    /// not know — a newer app version, or a user-configured entry (`FR-1.2.8`).
    ///
    /// Computed rather than stored, so there is exactly one source of truth for what this value
    /// is. Switch over it to handle the recognised cases and treat `nil` as "display the raw
    /// spelling and leave it alone".
    public var known: Term? {
        Term(rawValue: rawValue)
    }

    /// Whether this version recognises ``rawValue``.
    public var isKnown: Bool {
        known != nil
    }

    /// The raw spelling. Diagnostic output for tests and logs — it is not localised, and a term
    /// from a newer version has no display name here to fall back on.
    public var description: String {
        rawValue
    }
}

// MARK: - Codable

extension OpenVocabulary {
    /// Decodes the bare string form. **Never throws on an unrecognised spelling** — that is the
    /// entire point of the type; see the type's note on preserve-versus-degrade.
    ///
    /// A non-string value still throws. That is corruption, not a newer vocabulary — the same line
    /// ``Movement/init(from:)`` draws.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    /// Writes ``rawValue`` as a bare string — `"belt"`, not `{"rawValue": "belt"}`.
    ///
    /// Hand-written rather than synthesised, following `RoundingRule`'s precedent: synthesis over
    /// a single stored property would produce the wrapper object, and the bare string is what
    /// nests into an array of modifiers without a layer of noise. Changing it is a storage
    /// migration.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
