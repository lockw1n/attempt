import Foundation

/// The whole `exercises.json` payload: two version numbers and the entries (`TR-0.5.1`).
///
/// **The root is an object, not an array of entries.** An array cannot grow a version field without
/// a reshape, and `TR-0.5.2` publishes this same document to a CDN where the bundled and served
/// copies have to be the same bytes.
public struct SeedCatalogue: Decodable, Equatable, Sendable {
    /// The only ``schemaVersion`` this version of the app can read.
    public static let supportedSchemaVersion = 1

    /// Which shape the document is in — the question *"can this reader read it?"*.
    ///
    /// Bumped only when the fields change in a way an older reader cannot cope with; a corrected
    /// name or a new entry does not touch it. Unknown values are refused rather than tolerated,
    /// which is what lets `TR-0.5.3`'s fetcher fall back to the bundled copy by *asking* instead of
    /// by failing to parse.
    public let schemaVersion: Int

    /// Which edition of the content it is — the question *"is there anything newer?"*.
    ///
    /// Increases on every published change, including one that leaves ``schemaVersion`` alone. It is
    /// a separate number because one field cannot answer both questions: a content edit that bumped
    /// a shared version would lock out every older reader, and one that did not would be invisible
    /// to `TR-0.5.3`'s launch check.
    public let revision: Int

    /// The catalogue itself, in authoring order.
    ///
    /// Order is not a contract — nothing downstream may assume a parent precedes its variations,
    /// and the importer is what sorts them.
    public let exercises: [SeedExercise]

    /// The wire format's keys.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case exercises
    }

    /// Decodes the payload, refusing a key this version does not recognise.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.rejectUnrecognisedFields(from: decoder)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = try container.decode(Int.self, forKey: .revision)
        exercises = try container.decode([SeedExercise].self, forKey: .exercises)
    }
}
