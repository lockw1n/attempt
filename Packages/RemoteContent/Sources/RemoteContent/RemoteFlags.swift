/// The `/config/v1/flags.json` payload (`TR-0.5.2`): today, just the minimum-supported-version
/// kill switch `TR-0.5.4` names.
///
/// **What this type does not do.** Comparing ``minimumSupportedVersion`` against the running
/// build, and the blocking prompt that follows, are `T-0.55`'s — this is the wire shape alone, the
/// same split `T-0.53`'s brief draws between publishing a field and consuming it.
public struct RemoteFlags: Codable, Equatable, Sendable {
    /// The only ``schemaVersion`` this version of the app can read.
    public static let supportedSchemaVersion = 1

    /// Which shape the document is in. Same split as every other payload's pair — see
    /// `RemoteFormulas.schemaVersion`.
    public let schemaVersion: Int

    /// Which edition of the content it is.
    public let revision: Int

    /// The lowest app version still allowed to run, as a bare version string (`"1.2.0"`). Not
    /// parsed or compared here — see the type's note on what this payload does not do.
    public let minimumSupportedVersion: String

    /// Creates a document. Encoding is what the deploy script uses to produce the published
    /// payload. This initialiser does not reject a blank ``minimumSupportedVersion`` — that is
    /// `RemoteFlagsValidator`'s job, along with the other two fields, so a payload failing on more
    /// than one axis is reported in one pass.
    public init(schemaVersion: Int, revision: Int, minimumSupportedVersion: String) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.minimumSupportedVersion = minimumSupportedVersion
    }
}

// MARK: - Codable

extension RemoteFlags {
    /// The wire format's keys, declared rather than synthesised — the module-wide convention
    /// `RoundingRule` and `RPETable` set.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case minimumSupportedVersion
    }

    /// Decodes the shape ``CodingKeys`` describes. No field is checked here — see this type's own
    /// initialiser for why that is ``RemoteFlagsValidator``'s job.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = try container.decode(Int.self, forKey: .revision)
        minimumSupportedVersion = try container.decode(String.self, forKey: .minimumSupportedVersion)
    }

    /// Writes the three keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(revision, forKey: .revision)
        try container.encode(minimumSupportedVersion, forKey: .minimumSupportedVersion)
    }
}
