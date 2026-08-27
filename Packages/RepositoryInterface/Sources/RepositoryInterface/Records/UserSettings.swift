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

    /// Which exercises the dashboard tiles an estimated max for, in the order they appear
    /// (`FR-1.9.1`), or `nil` where the user has never said.
    ///
    /// **Optional rather than empty-by-default, because "none" is a choice they can make.** A lifter
    /// who removes every tile gets the screen's insufficient-data state; one who has never opened the
    /// picker gets the three competition lifts. One array cannot say both, and defaulting to the
    /// three would make the first user's removal look like a fresh install on the next launch.
    ///
    /// **Ordered, and duplicates are not refused here.** The order is the one the tiles are drawn in,
    /// which is the user's arrangement rather than a set; a repeated identifier draws the same tile
    /// twice, and refusing it is the picker's business rather than this record's — see this module's
    /// header on validation.
    public let dashboardExerciseIDs: [UUID]?

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
        defaultRoundingStrategy: RoundingStrategy,
        dashboardExerciseIDs: [UUID]? = nil
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
        self.dashboardExerciseIDs = dashboardExerciseIDs
    }
    /// This row with a different dashboard tile selection (`FR-1.9.1`).
    ///
    /// **A method here rather than a re-listing of every property at the call site.** A save
    /// assembled from a screen's own copy is the stale-write shape: a caller that never read a
    /// column cannot rebuild the row by hand without clearing it, and this record has gained a
    /// column once already.
    ///
    /// - Parameter exerciseIDs: The exercises to tile, in the order to draw them.
    /// - Returns: The row to save.
    public func tiling(_ exerciseIDs: [UUID]) -> UserSettings {
        UserSettings(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            userID: userID,
            displayUnit: displayUnit,
            e1RMFormula: e1RMFormula,
            theme: theme,
            defaultRoundingIncrement: defaultRoundingIncrement,
            defaultRoundingStrategy: defaultRoundingStrategy,
            dashboardExerciseIDs: exerciseIDs)
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
        case dashboardExerciseIDs
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
                or: RecordVocabulary.roundingStrategy),
            dashboardExerciseIDs: try container.decodeIfPresent(
                [UUID].self, forKey: .dashboardExerciseIDs)
        )
    }

    /// Writes the eleven keys in declaration order. ``dashboardExerciseIDs`` is absent rather than
    /// null where the user has never chosen, on ``Exercise``'s rule: an omitted key and a null one
    /// decode alike, and the shorter of the two is what a settings row that has never been
    /// configured actually is.
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
        try container.encodeIfPresent(dashboardExerciseIDs, forKey: .dashboardExerciseIDs)
    }
}
