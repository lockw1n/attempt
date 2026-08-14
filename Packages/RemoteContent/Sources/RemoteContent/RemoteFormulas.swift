import PowerliftingCore

/// The `/content/v1/formulas.json` payload (`TR-0.5.2`): a versioned wrapper around the RPE/RIR
/// chart ``RPEBased`` reads.
///
/// **Two version numbers, same split as `exercises.json`.** ``schemaVersion`` answers "can this
/// reader read it" and is refused when unrecognised; ``revision`` answers "is there anything
/// newer" and increases on every published edit, including one that leaves ``schemaVersion``
/// alone.
///
/// **``verified`` is the provenance flag `RPETableStandard.swift` promises.** ``RPETable/standard``
/// is a transcription that has not been checked against a primary publication (`G-6.2`), and a
/// remote table is read as more authoritative than a bundled one, not less — so a served table
/// says whether it has been checked rather than carrying the caveat forward in silence. The prose
/// behind the flag stays on ``RPETable/standard``'s doc comment; this is the one field, not a
/// second copy of the paragraph.
public struct RemoteFormulas: Codable, Equatable, Sendable {
    /// The only ``schemaVersion`` this version of the app can read.
    public static let supportedSchemaVersion = 1

    /// Which shape the document is in. See ``schemaVersion``'s counterpart on `SeedCatalogue` for
    /// the fuller argument; the split is the same one, applied here.
    public let schemaVersion: Int

    /// Which edition of the content it is.
    public let revision: Int

    /// Whether ``rpeTable`` has been checked against a primary publication. `false` for the
    /// transcription ``RPETable/standard`` ships as; a corrected table sets it `true`.
    public let verified: Bool

    /// The chart itself, in ``RPETable``'s own wire shape.
    public let rpeTable: RPETable

    /// Creates a document. Encoding is what the deploy script uses to turn ``RPETable/standard``
    /// into the published payload; nothing downstream constructs one by hand. Unlike
    /// `exercises.json`'s `SeedCatalogue`, this initialiser does not reject a non-positive
    /// ``revision`` or an unsupported ``schemaVersion`` — `RemoteFormulasValidator` is where both
    /// are checked, the same split `SeedCatalogueValidator` uses, so a payload failing on more than
    /// one axis is reported in one pass rather than stopping at the first.
    public init(schemaVersion: Int, revision: Int, verified: Bool, rpeTable: RPETable) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.verified = verified
        self.rpeTable = rpeTable
    }
}

// MARK: - Codable

extension RemoteFormulas {
    /// The wire format's keys, declared rather than synthesised so key order is a decision — the
    /// module-wide convention `RoundingRule` and `RPETable` set.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case verified
        case rpeTable
    }

    /// Decodes the shape ``CodingKeys`` describes. Only ``rpeTable`` can fail here — its own
    /// initialiser's guards run inside ``RPETable``'s decoding. ``schemaVersion`` and ``revision``
    /// are not checked here — see this type's own initialiser for why that is
    /// ``RemoteFormulasValidator``'s job.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = try container.decode(Int.self, forKey: .revision)
        verified = try container.decode(Bool.self, forKey: .verified)
        rpeTable = try container.decode(RPETable.self, forKey: .rpeTable)
    }

    /// Writes the four keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(revision, forKey: .revision)
        try container.encode(verified, forKey: .verified)
        try container.encode(rpeTable, forKey: .rpeTable)
    }
}
