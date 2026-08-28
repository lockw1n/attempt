import Foundation
import PowerliftingCore

/// The user's preferences, plus the anonymous identity their data is claimed under (`TR-0.3.8`).
///
/// **The two identities are `let` and everything a store or a screen legitimately rewrites is
/// `var`**, which is the shape a settings screen needs: a caller reads the row, moves the one field
/// the user touched and saves the copy. A save assembled field by field from a screen's own
/// knowledge is the stale-write shape — a caller that never read a column cannot rebuild the row by
/// hand without clearing it, and this record has gained columns twice.
public struct UserSettings: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public var createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public var updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public var deletedAt: Date?

    /// The anonymous local user id (`TR-1.10`), minted once by
    /// ``SettingsRepository/settings()`` and never writable afterwards.
    ///
    /// `FR-5.1.2` claims every local row with it, so a layer able to rewrite it could hand the
    /// user's training history to a different account. A save carrying a different value is
    /// refused rather than ignored — see ``RepositoryError/identityAlreadyEstablished(recordID:)``.
    public let userID: UUID

    /// Which unit weights are shown in (`G-3.1`). Display only: storage is grams and switching
    /// never rewrites data (`G-3.2`).
    public var displayUnit: MassUnit

    /// The step displayed weights read to (`G-3.3`), or `nil` where the user has never chosen.
    ///
    /// **Optional rather than defaulted, because the factory step depends on the unit** — 0.5 kg
    /// but 1 lb. A row that stored 500 on the user's behalf would silently become half-pound steps
    /// the first time they switched units, which is not what they were shown when they left it
    /// alone. ``weightDisplay`` is what a screen renders through.
    public var displayPrecision: DisplayPrecision?

    /// Which estimator every e1RM is computed with (`FR-1.10.1`).
    ///
    /// Changing it changes every estimate retroactively (`FR-1.7.3`) and is its own personal-record
    /// invalidation trigger (`TR-1.6`), separate from any computation version.
    public var e1RMFormula: E1RMFormulaID

    /// How many days back an estimated max looks for its best qualifying set (`FR-1.7.1`).
    ///
    /// Days rather than a window type: the window lives a layer up, over `Calendar`, and this
    /// module reaches no calendar. Values below one are the window's to clamp, not this record's to
    /// refuse — see this module's header on validation.
    public var e1RMLookbackDays: Int

    /// Which appearance the user picked (`FR-1.10.2`).
    public var theme: ThemePreference

    /// Whether the screen is held awake while a workout is in progress (`NFR-1.9`).
    ///
    /// The preference alone; combining it with whether a workout is actually on is the app's, and
    /// turning the idle timer off is UIKit's.
    public var keepScreenAwake: Bool

    /// The loadable step new exercises get by default (`FR-1.5.1.6`).
    ///
    /// Unvalidated: a value below one gram maps to no `RoundingRule`, and the refusal belongs to
    /// the projection rather than to this property.
    public var defaultRoundingIncrement: Weight

    /// The direction half of the same default.
    public var defaultRoundingStrategy: RoundingStrategy

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
    public var dashboardExerciseIDs: [UUID]?

    /// Creates a settings record. No property is validated; see this module's header.
    ///
    /// The three defaulted preferences are a convenience for a caller rebuilding a row, not the
    /// authority on what a fresh install gets — that is ``SettingsRepository/settings()``'s.
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
        displayPrecision: DisplayPrecision? = nil,
        e1RMLookbackDays: Int = UserSettings.defaultE1RMLookbackDays,
        keepScreenAwake: Bool = UserSettings.defaultKeepScreenAwake,
        dashboardExerciseIDs: [UUID]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.userID = userID
        self.displayUnit = displayUnit
        self.displayPrecision = displayPrecision
        self.e1RMFormula = e1RMFormula
        self.e1RMLookbackDays = e1RMLookbackDays
        self.theme = theme
        self.keepScreenAwake = keepScreenAwake
        self.defaultRoundingIncrement = defaultRoundingIncrement
        self.defaultRoundingStrategy = defaultRoundingStrategy
        self.dashboardExerciseIDs = dashboardExerciseIDs
    }

    /// `FR-1.7.1`'s default window, in days, and the only place that number is written.
    ///
    /// Here rather than beside the window type: it is what a user who has never configured one
    /// gets, which makes it a preference default rather than a property of the window.
    public static let defaultE1RMLookbackDays = 90

    /// `NFR-1.9` read as written: the screen stays awake, and the toggle is the way out of it
    /// rather than the way in. A lifter's hands are chalked and the phone is on the floor.
    public static let defaultKeepScreenAwake = true

    /// How a weight is rendered under this row (`G-3.1`, `G-3.3`) — the unit, and the step the
    /// user chose or the factory one for that unit.
    public var weightDisplay: WeightDisplay {
        guard let displayPrecision else { return WeightDisplay(unit: displayUnit) }
        return WeightDisplay(unit: displayUnit, precision: displayPrecision)
    }

    /// The loadable-weight rule this row's two rounding columns describe (`FR-1.5.1.6`), or `nil`
    /// where the stored increment is below one gram.
    ///
    /// Deliberately not ``weightDisplay``'s neighbour: that decides what a number reads as, this
    /// decides what can go on a bar, and `FR-2.3.3` already cost Phase 0 an open gap for
    /// conflating two rounding authorities.
    public var defaultRoundingRule: RoundingRule? {
        RoundingRule(increment: defaultRoundingIncrement, strategy: defaultRoundingStrategy)
    }

    /// This row's identity and audit stamps, carrying `other`'s preferences.
    ///
    /// **The one place a preference-only write is spelled out**, and it is here rather than in a
    /// store because the list has to sit beside the declarations it enumerates: every column added
    /// to this record has to be added to it, and a store that kept its own copy would drop the new
    /// one silently — the write would land and the preference would not.
    ///
    /// - Parameter other: The record whose preferences to take.
    /// - Returns: This row's identity, with `other`'s preferences on it.
    public func carryingPreferences(of other: UserSettings) -> UserSettings {
        UserSettings(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            userID: userID,
            displayUnit: other.displayUnit,
            e1RMFormula: other.e1RMFormula,
            theme: other.theme,
            defaultRoundingIncrement: other.defaultRoundingIncrement,
            defaultRoundingStrategy: other.defaultRoundingStrategy,
            displayPrecision: other.displayPrecision,
            e1RMLookbackDays: other.e1RMLookbackDays,
            keepScreenAwake: other.keepScreenAwake,
            dashboardExerciseIDs: other.dashboardExerciseIDs)
    }

    /// This row with a different dashboard tile selection (`FR-1.9.1`).
    ///
    /// - Parameter exerciseIDs: The exercises to tile, in the order to draw them.
    /// - Returns: The row to save.
    public func tiling(_ exerciseIDs: [UUID]) -> UserSettings {
        var updated = self
        updated.dashboardExerciseIDs = exerciseIDs
        return updated
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
        case displayPrecision
        case e1RMFormula
        case e1RMLookbackDays
        case theme
        case keepScreenAwake
        case defaultRoundingIncrement
        case defaultRoundingStrategy
        case dashboardExerciseIDs
    }

    /// ``displayPrecision``, or `nil` where the key is absent, holds something this version cannot
    /// read, or holds a step below one milli-unit.
    ///
    /// **Resolves rather than throws, which the type's own `Codable` conformance does not.**
    /// `DisplayPrecision` refuses a zero step on the way in — correctly, since something
    /// downstream divides by it — but refusing it *here* would take the theme, the unit, the
    /// rounding defaults and ``userID`` down with one unreadable preference. The store's mapping
    /// layer already made this choice for the same column; the two ingest paths agree.
    ///
    /// - Parameter container: The keyed container being decoded.
    /// - Returns: The step, or `nil`.
    private static func decodedPrecision(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> DisplayPrecision? {
        // `try?` flattens the optional, so an absent key and an unreadable one arrive alike — which
        // is what this wants: both mean "no step to restore", and neither is worth a third answer.
        guard let milliUnits = try? container.decodeIfPresent(Int.self, forKey: .displayPrecision)
        else { return nil }
        return DisplayPrecision(milliUnits: milliUnits)
    }

    /// Decodes the keyed shape on ``CodingKeys``.
    ///
    /// All four preference vocabularies resolve rather than throw, ``e1RMFormula`` included — a
    /// formula name from a newer version must not take the theme, the unit and the rounding
    /// defaults down with it, still less ``userID``.
    ///
    /// The three keys this record gained after its first wire format are absent-tolerant, on the
    /// same rule: a backup written before they existed restores every preference it does carry.
    /// ``displayPrecision`` is *value*-tolerant too — see ``decodedPrecision(from:)``.
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
            displayPrecision: Self.decodedPrecision(from: container),
            e1RMLookbackDays: try container.decodeIfPresent(Int.self, forKey: .e1RMLookbackDays)
                ?? UserSettings.defaultE1RMLookbackDays,
            keepScreenAwake: try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwake)
                ?? UserSettings.defaultKeepScreenAwake,
            dashboardExerciseIDs: try container.decodeIfPresent(
                [UUID].self, forKey: .dashboardExerciseIDs)
        )
    }

    /// Writes the fourteen keys in declaration order. ``dashboardExerciseIDs`` and
    /// ``displayPrecision`` are absent rather than null where the user has never chosen, on
    /// ``Exercise``'s rule: an omitted key and a null one decode alike, and the shorter of the two
    /// is what a settings row that has never been configured actually is.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(userID, forKey: .userID)
        try container.encodeVocabulary(displayUnit, forKey: .displayUnit)
        try container.encodeIfPresent(displayPrecision, forKey: .displayPrecision)
        try container.encodeVocabulary(e1RMFormula, forKey: .e1RMFormula)
        try container.encode(e1RMLookbackDays, forKey: .e1RMLookbackDays)
        try container.encodeVocabulary(theme, forKey: .theme)
        try container.encode(keepScreenAwake, forKey: .keepScreenAwake)
        try container.encode(defaultRoundingIncrement, forKey: .defaultRoundingIncrement)
        try container.encodeVocabulary(defaultRoundingStrategy, forKey: .defaultRoundingStrategy)
        try container.encodeIfPresent(dashboardExerciseIDs, forKey: .dashboardExerciseIDs)
    }
}
