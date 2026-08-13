import Foundation

/// One reason a payload is not fit to ship.
///
/// Every case names the entry it is about, because the audience is someone holding a file of eighty
/// hand-written entries.
public enum SeedValidationFailure: Equatable, Sendable {
    /// The bytes are not a payload at all — malformed JSON, a missing field, an unparseable UUID.
    /// Carries the decoder's own description, which names the key and the type.
    case undecodable(String)

    /// A key no version of this schema declares. Almost always a typo, and `Codable` would drop it
    /// in silence.
    case unrecognisedField(String)

    /// A shape this reader cannot read. See ``SeedCatalogue/schemaVersion``.
    case unsupportedSchemaVersion(Int)

    /// A ``SeedCatalogue/revision`` below one, which no published edition has.
    case nonPositiveRevision(Int)

    /// Fewer entries than the caller requires. `TR-0.5.1`'s floor of eighty is asked for by the
    /// catalogue's own suite, not by every call.
    case tooFewExercises(count: Int, minimum: Int)

    /// Two entries share an identity. The second one is unreachable, and a re-import would
    /// overwrite the first.
    case duplicateID(UUID)

    /// A name that is empty or only whitespace, which no picker can display.
    case blankName(UUID)

    /// A `parentExerciseID` naming an entry the payload does not contain.
    case danglingParent(exercise: UUID, parent: UUID)

    /// A parent chain that closes on itself, listed from the first member reached. A single element
    /// is an entry that is its own parent.
    case parentCycle([UUID])

    /// A vocabulary spelling no domain type recognises. Three of the four resolve such a value to
    /// `.other` on decode, so this is the only place it is refused.
    case unknownVocabulary(exercise: UUID, field: SeedVocabularyField, value: String)

    /// An implement count below one. Nothing downstream rejects it — the stored entity and the DTO
    /// layer both name this validator as where it is caught — and it silently makes every tonnage
    /// figure the entry contributes to wrong.
    case nonPositiveImplementCount(exercise: UUID, count: Int)
}

extension SeedValidationFailure {
    /// A failure's category, independent of the values it carries.
    ///
    /// It exists so that a suite can assert every kind is covered by a fixture: an enum with
    /// associated values cannot be `CaseIterable`, and a list of kinds written out by hand is the
    /// thing that goes stale when an eleventh failure lands.
    public enum Kind: String, CaseIterable, Sendable {
        /// See ``SeedValidationFailure/undecodable(_:)``.
        case undecodable
        /// See ``SeedValidationFailure/unrecognisedField(_:)``.
        case unrecognisedField
        /// See ``SeedValidationFailure/unsupportedSchemaVersion(_:)``.
        case unsupportedSchemaVersion
        /// See ``SeedValidationFailure/nonPositiveRevision(_:)``.
        case nonPositiveRevision
        /// See ``SeedValidationFailure/tooFewExercises(count:minimum:)``.
        case tooFewExercises
        /// See ``SeedValidationFailure/duplicateID(_:)``.
        case duplicateID
        /// See ``SeedValidationFailure/blankName(_:)``.
        case blankName
        /// See ``SeedValidationFailure/danglingParent(exercise:parent:)``.
        case danglingParent
        /// See ``SeedValidationFailure/parentCycle(_:)``.
        case parentCycle
        /// See ``SeedValidationFailure/unknownVocabulary(exercise:field:value:)``.
        case unknownVocabulary
        /// See ``SeedValidationFailure/nonPositiveImplementCount(exercise:count:)``.
        case nonPositiveImplementCount
    }

    /// This failure's ``Kind``.
    public var kind: Kind {
        switch self {
        case .undecodable: .undecodable
        case .unrecognisedField: .unrecognisedField
        case .unsupportedSchemaVersion: .unsupportedSchemaVersion
        case .nonPositiveRevision: .nonPositiveRevision
        case .tooFewExercises: .tooFewExercises
        case .duplicateID: .duplicateID
        case .blankName: .blankName
        case .danglingParent: .danglingParent
        case .parentCycle: .parentCycle
        case .unknownVocabulary: .unknownVocabulary
        case .nonPositiveImplementCount: .nonPositiveImplementCount
        }
    }
}

extension SeedValidationFailure: CustomStringConvertible {
    /// A line an author can act on without opening the validator.
    public var description: String {
        switch self {
        case .undecodable(let detail):
            "the payload could not be decoded: \(detail)"
        case .unrecognisedField(let name):
            "unrecognised field '\(name)' — this schema declares no such key"
        case .unsupportedSchemaVersion(let found):
            "schemaVersion \(found) is not readable here; this build reads "
                + "\(SeedCatalogue.supportedSchemaVersion)"
        case .nonPositiveRevision(let found):
            "revision \(found) is not a published edition; revisions start at 1"
        case .tooFewExercises(let count, let minimum):
            "\(count) exercise(s), and at least \(minimum) are required"
        case .duplicateID(let id):
            "\(id) is used by more than one exercise"
        case .blankName(let id):
            "\(id) has a blank name"
        case .danglingParent(let exercise, let parent):
            "\(exercise) names parent \(parent), which the payload does not contain"
        case .parentCycle(let cycle):
            "the parent chain \(cycle.map(\.uuidString).joined(separator: " → ")) closes on itself"
        case .unknownVocabulary(let exercise, let field, let value):
            "\(exercise) has \(field.rawValue) '\(value)'; accepted: "
                + field.acceptedValues.joined(separator: ", ")
        case .nonPositiveImplementCount(let exercise, let count):
            "\(exercise) loads \(count) implement(s); at least 1 is required"
        }
    }
}
