/// A prescription written by a version that knows a type this one does not, kept whole.
///
/// `NFR-2.3` requires an unknown prescription type to degrade gracefully rather than corrupt the
/// program, and a program is the user's own data with no upstream copy — so the answer is to
/// preserve rather than to degrade, unlike ``Movement`` and its neighbours. What is preserved is
/// the discriminator, the schema version it arrived under, and every other key of the object.
///
/// **``schemaVersion`` is the version this value came from, not the current one.** Re-encoding it
/// as the current version would claim that this app understood it.
///
/// Nothing here interprets ``payload``. A caller's only reasonable moves are to show the raw
/// ``kind``, refuse to resolve it, and write it back unchanged.
public struct UnrecognisedPrescription: Sendable, Hashable {
    /// The `type` discriminator exactly as it arrived. Never a spelling this version recognises.
    public let kind: String

    /// The schema version the enclosing object declared. At least 1.
    public let schemaVersion: Int

    /// Every key of the object except the envelope's `version` and `type`, which this type never
    /// holds — see ``init(kind:schemaVersion:payload:)``.
    public let payload: [String: PreservedValue]

    /// Wraps a prescription this version cannot interpret.
    ///
    /// - Returns: `nil` if `kind` is a type this version *does* recognise, if `schemaVersion` is
    ///   below 1, or if `payload` carries a reserved envelope key.
    ///
    ///   The first check is the one that keeps encoding injective: without it this type could hold
    ///   `kind: "fixedWeight"`, giving two values that encode identically to
    ///   ``Prescription/fixedWeight(_:)``'s — the same loss of injectivity that made
    ///   ``OpenVocabulary`` a struct rather than a two-case enum. The third closes the same door
    ///   from the other side. A payload holding `type` would be written into the same object as
    ///   the envelope's own `type`, and which of the two survives is the encoder's business: a
    ///   dictionary-backed one keeps the payload's, so the value decodes back as a *different*
    ///   prescription. Refused rather than dropped, because silently discarding a key is the kind
    ///   of rewrite `G-1.6` rules out.
    public init?(kind: String, schemaVersion: Int, payload: [String: PreservedValue] = [:]) {
        guard PrescriptionKind(rawValue: kind) == nil, schemaVersion >= 1,
            payload.keys.allSatisfy({ !AnyCodingKey.envelope.contains($0) })
        else { return nil }
        self.init(preservingKind: kind, schemaVersion: schemaVersion, payload: payload)
    }

    /// The decoder's entry point, where both of ``init(kind:schemaVersion:payload:)``'s conditions
    /// have already been established by the parse that got here.
    init(preservingKind kind: String, schemaVersion: Int, payload: [String: PreservedValue]) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}
