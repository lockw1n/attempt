/// A value drawn from a vocabulary expected to grow, kept as the raw spelling so a term this
/// version does not recognise survives a round trip unchanged.
///
/// This is the module's *tolerate + preserve* answer to an unrecognised raw value — one of four;
/// the rule that picks between them is in CLAUDE.md. It applies because nothing re-supplies a set
/// modifier the user logged, so dropping one that arrived from a newer version destroys the only
/// copy. `FR-1.2.8` makes the modifier list configurable, so such values exist by design.
///
/// **It is canonical by construction: the raw spelling is the only stored property.** Do not
/// "improve" this into a `known`/`unknown` enum — two cases would admit `.unknown("belt")`
/// alongside `.known(.belt)`, values that compare unequal, hash differently and encode
/// identically, so encoding would not be injective and a duplicate check would miss a real
/// duplicate. ``known`` recovers the term when there is one.
///
/// One residual divergence, the other way: equality is `String`'s canonical equivalence, so a
/// precomposed and a decomposed `é` are the same value here while their UTF-8 differs. Two equal
/// values can encode to different bytes, and a deduplicating caller keeps whichever it saw first.
/// Round-tripping is unaffected, and every built-in term is ASCII.
///
/// - Parameter Term: The vocabulary this version knows, as a `String`-backed enum. Never stored —
///   only consulted by ``known`` — so equality, hashing and the wire format depend on ``rawValue``
///   alone.
public struct OpenVocabulary<Term>: Sendable, Hashable, Codable, CustomStringConvertible
where Term: RawRepresentable, Term.RawValue == String {
    /// The persisted spelling, exactly as written or decoded.
    ///
    /// Any `String` is accepted, including one this version has never seen and the empty string.
    /// Validating is the caller's business — being the place an unvalidatable value can survive is
    /// this type's whole job.
    public let rawValue: String

    /// Wraps a raw spelling, recognised or not.
    ///
    /// - Parameter rawValue: The persisted spelling. Not normalised in any way — case, spacing and
    ///   the empty string round-trip verbatim, because normalising would silently rewrite a value
    ///   the app cannot interpret, and `G-1.6` forbids modifying logged data.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Wraps a term this version knows about — `SetModifier(.belt)`.
    public init(_ term: Term) {
        self.rawValue = term.rawValue
    }

    /// The recognised term, or `nil` when ``rawValue`` belongs to a vocabulary this version does
    /// not know — a newer app version, or a user-configured entry (`FR-1.2.8`).
    ///
    /// Computed rather than stored, so there is one source of truth for what this value is. Treat
    /// `nil` as "display the raw spelling and leave it alone".
    public var known: Term? {
        Term(rawValue: rawValue)
    }

    /// Whether this version recognises ``rawValue``.
    public var isKnown: Bool {
        known != nil
    }

    /// The raw spelling. Diagnostic output — not localised, and a term from a newer version has no
    /// display name to fall back on.
    public var description: String {
        rawValue
    }
}

// MARK: - Codable

extension OpenVocabulary {
    /// Decodes the bare string form. **Never throws on an unrecognised spelling** — that is the
    /// point of the type. A non-string value still throws: that is corruption, not a newer
    /// vocabulary.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    /// Writes ``rawValue`` as a bare string — `"belt"`, not `{"rawValue": "belt"}`.
    ///
    /// Hand-written rather than synthesised: synthesis over a single stored property would produce
    /// the wrapper object, and the bare string is what nests into an array of modifiers without a
    /// layer of noise. Changing it is a storage migration.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
