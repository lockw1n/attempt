import Foundation
import PowerliftingCore

/// The user's preferences, plus the anonymous identity their data is claimed under (`TR-0.3.8`).
public struct UserSettings: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The anonymous local user id (`TR-1.10`), minted once by
    /// ``SettingsRepository/settings()`` and never writable afterwards.
    ///
    /// `FR-5.1.2` claims every local row with it, so a layer able to rewrite it could hand the
    /// user's training history to a different account. A save carrying a different value is
    /// refused rather than ignored — see ``RepositoryError/identityAlreadyEstablished(recordID:)``.
    public let userID: UUID

    /// Which unit weights are shown in (`G-3.1`). Display only: storage is grams and switching
    /// never rewrites data (`G-3.2`).
    public let displayUnit: MassUnit

    /// Which estimator every e1RM is computed with (`FR-1.10.1`).
    ///
    /// Changing it changes every estimate retroactively (`FR-1.7.3`) and is its own personal-record
    /// invalidation trigger (`TR-1.6`), separate from any computation version.
    public let e1RMFormula: E1RMFormulaID

    /// Which appearance the user picked (`FR-1.10.2`).
    public let theme: ThemePreference

    /// The loadable step new exercises get by default (`FR-1.5.1.6`).
    ///
    /// Unvalidated: a value below one gram maps to no `RoundingRule`, and the refusal belongs to
    /// the projection rather than to this property.
    public let defaultRoundingIncrement: Weight

    /// The direction half of the same default.
    public let defaultRoundingStrategy: RoundingStrategy

    /// Creates a settings record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        userID: UUID,
        displayUnit: MassUnit,
        e1RMFormula: E1RMFormulaID,
        theme: ThemePreference,
        defaultRoundingIncrement: Weight,
        defaultRoundingStrategy: RoundingStrategy
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.userID = userID
        self.displayUnit = displayUnit
        self.e1RMFormula = e1RMFormula
        self.theme = theme
        self.defaultRoundingIncrement = defaultRoundingIncrement
        self.defaultRoundingStrategy = defaultRoundingStrategy
    }
}

// MARK: - Codable

extension UserSettings {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case userID
        case displayUnit
        case e1RMFormula
        case theme
        case defaultRoundingIncrement
        case defaultRoundingStrategy
    }

    /// Decodes the keyed shape on ``CodingKeys``.
    ///
    /// All four preference vocabularies resolve rather than throw, ``e1RMFormula`` included — a
    /// formula name from a newer version must not take the theme, the unit and the rounding
    /// defaults down with it, still less ``userID``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            userID: try container.decode(UUID.self, forKey: .userID),
            displayUnit: try container.decodeVocabulary(
                MassUnit.self, forKey: .displayUnit, or: RecordVocabulary.displayUnit),
            e1RMFormula: try container.decodeVocabulary(
                E1RMFormulaID.self, forKey: .e1RMFormula, or: RecordVocabulary.e1RMFormula),
            theme: try container.decodeVocabulary(
                ThemePreference.self, forKey: .theme, or: RecordVocabulary.theme),
            defaultRoundingIncrement: try container.decode(Weight.self, forKey: .defaultRoundingIncrement),
            defaultRoundingStrategy: try container.decodeVocabulary(
                RoundingStrategy.self,
                forKey: .defaultRoundingStrategy,
                or: RecordVocabulary.roundingStrategy)
        )
    }

    /// Writes the ten keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(userID, forKey: .userID)
        try container.encodeVocabulary(displayUnit, forKey: .displayUnit)
        try container.encodeVocabulary(e1RMFormula, forKey: .e1RMFormula)
        try container.encodeVocabulary(theme, forKey: .theme)
        try container.encode(defaultRoundingIncrement, forKey: .defaultRoundingIncrement)
        try container.encodeVocabulary(defaultRoundingStrategy, forKey: .defaultRoundingStrategy)
    }
}
