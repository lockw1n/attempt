import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData

/// The user's preferences, plus the anonymous identity their data is claimed under (`TR-0.3.8`).
///
/// **``userID`` is minted once, by the first-launch bootstrap, and never here.** `TR-1.10` creates
/// it at first launch and `FR-5.1.2` claims every local row with it, so a schema that could
/// manufacture one would manufacture an *account*. That is why it inverts `id`'s rule: `id`
/// defaults to `UUID()` because the default mints an identity, and this defaults to
/// `SchemaDefaults.unlinkedID` for exactly the same reason — the identity is not this layer's to
/// mint. `init` takes it, there is no setter, and nothing in the module can rewrite it.
///
/// **"Once" is a repository invariant, not a schema one.** Nothing stops two settings rows
/// existing, each with its own ``userID``, so the bootstrap has to find-or-create rather than create
/// (`TR-0.4.1`, `TR-0.4.3`) — the same shape as `id` uniqueness and `EquipmentProfileEntity`'s
/// default flag.
///
/// **An unreadable preference costs that preference and nothing else.** Every vocabulary column
/// holds a raw `String`, so a formula name from a newer version cannot fail to decode and cannot
/// take theme, unit or rounding down with it; the fallback is the repository's (`TR-0.4.3`).
@Model
final class UserSettingsEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The anonymous local user id (`TR-1.10`). See the type's note for why this is `private(set)`
    /// and why it has no writer.
    private(set) var userID: UUID = SchemaDefaults.unlinkedID

    /// ``PowerliftingCore/MassUnit``'s raw value — which unit weights are shown in (`G-3.1`).
    /// Display only: storage is always grams and switching never rewrites data (`G-3.2`).
    var displayUnitRawValue: String = SchemaDefaults.displayUnit

    /// ``PowerliftingCore/E1RMFormulaID``'s raw value (`FR-1.10.1`).
    ///
    /// Changing it changes every estimate retroactively (`FR-1.7.3`) and is its own personal-record
    /// invalidation trigger (`TR-1.6`), separate from any `computationVersion`.
    var e1RMFormulaRawValue: String = SchemaDefaults.e1RMFormula

    /// The step displayed weights read to, in thousandths of the display unit (`G-3.3`), or `nil`
    /// where the user has never chosen.
    ///
    /// **Optional rather than defaulted**, which is the second column here where the two differ in
    /// meaning: the factory step depends on the unit — 0.5 kg but 1 lb — so a number stored on the
    /// user's behalf would become half-pound steps the first time they switched units. The record
    /// derives from the unit when this is absent.
    var displayPrecisionMilliUnits: Int?

    /// ``RepositoryInterface/ThemePreference``'s raw value (`FR-1.10.2`).
    var themeRawValue: String = SchemaDefaults.theme

    /// How many days back an estimated max looks (`FR-1.7.1`).
    var e1RMLookbackDays: Int = SchemaDefaults.e1RMLookbackDays

    /// Whether the screen is held awake during a workout (`NFR-1.9`).
    ///
    /// A defaulted `Bool`, which `SchemaV1` warns about — but the warning is about a flag that
    /// makes a claim on rows this app never wrote. This one is a preference about what the app
    /// does next, and the default is the requirement read as written.
    var keepScreenAwake: Bool = SchemaDefaults.keepScreenAwake

    /// The loadable step new exercises get by default, in grams (`FR-1.5.1.6`).
    ///
    /// Unvalidated: a value below one gram maps to no `RoundingRule`, and the refusal is the
    /// mapping's rather than this column's.
    var defaultRoundingIncrementGrams: Int = SchemaDefaults.roundingIncrementGrams

    /// ``PowerliftingCore/RoundingStrategy``'s raw value, the direction half of the same default.
    var defaultRoundingStrategyRawValue: String = SchemaDefaults.roundingStrategy

    /// Which exercises the dashboard tiles an estimated max for, in the order they are drawn
    /// (`FR-1.9.1`), or `nil` where the user has never chosen.
    ///
    /// **Optional rather than defaulted to empty**, which is the one column here where the two differ
    /// in meaning: `nil` is "never configured" and `[]` is "configured to none", and the screen shows
    /// the competition lifts for the first and its insufficient-data state for the second.
    ///
    /// **Identifiers and not a relationship**, on the rule every join key here follows (`G-2.5`
    /// forbids the constraint that would make one safe): a tiled exercise that is later deleted
    /// leaves a dangling id, which the dashboard drops rather than resolving to a row.
    var dashboardExerciseIDs: [UUID]?

    /// ``RepositoryInterface/RecentRecordsScope``'s raw value — which exercises `FR-1.6.5`'s feed
    /// reports on (`FR-16.3.1`).
    ///
    /// **The first column in this module added after schema v1, and it takes the branch `SchemaV1`'s
    /// second rule allows.** A backfilled row asserts the dashboard lifts, which is a claim about
    /// what the app does next rather than about training that happened — the same ground
    /// ``keepScreenAwake`` stands on — and it is `FR-16.3.1`'s own default, so a migrated row and a
    /// fresh install agree.
    var recentRecordsScopeRawValue: String = SchemaDefaults.recentRecordsScope

    /// The exercises the feed reports on under
    /// ``RepositoryInterface/RecentRecordsScope/chosen``, or `nil` where the lifter never chose.
    ///
    /// Optional and identifiers rather than a relationship, both for ``dashboardExerciseIDs``'
    /// reasons — and optional is what `SchemaV1`'s first rule asks of a column added later anyway.
    var recentRecordsExerciseIDs: [UUID]?

    /// The repetition half of the chosen schemes (`FR-16.3.2`), or `nil` where they are derived.
    ///
    /// **A pair of parallel arrays rather than one column of pairs**, which is
    /// `EquipmentProfileEntity`'s plate inventory again: SwiftData stores an array of scalars and
    /// `G-2.5` forbids the relationship that would carry a struct, so a `(reps, sets)` list is two
    /// columns written together. `nil` on both is the derived case — see
    /// ``RepositoryInterface/RecentRecordsSchemes/stored(reps:sets:)``, which is the only reader.
    var recentRecordsSchemeReps: [Int]?

    /// The set-count half of the same pair. See ``recentRecordsSchemeReps``.
    var recentRecordsSchemeSets: [Int]?

    /// Whether the feed shows a scheme's first-ever record (`FR-16.3.4`).
    ///
    /// A defaulted `Bool` added after v1, which `SchemaV1`'s second rule warns about — and it is
    /// ``keepScreenAwake``'s answer: the flag decides what a screen draws next rather than making a
    /// claim about a set that was logged before the column existed.
    var recentRecordsShowsBaselines: Bool = SchemaDefaults.recentRecordsShowsBaselines

    init(
        id: UUID = UUID(),
        userID: UUID,
        displayUnit: MassUnit,
        e1RMFormula: E1RMFormulaID,
        theme: ThemePreference,
        defaultRoundingIncrementGrams: Int,
        defaultRoundingStrategy: RoundingStrategy,
        displayPrecisionMilliUnits: Int? = nil,
        e1RMLookbackDays: Int = SchemaDefaults.e1RMLookbackDays,
        keepScreenAwake: Bool = SchemaDefaults.keepScreenAwake,
        dashboardExerciseIDs: [UUID]? = nil,
        recentRecordsScope: RecentRecordsScope = .dashboardLifts,
        recentRecordsExerciseIDs: [UUID]? = nil,
        recentRecordsSchemeReps: [Int]? = nil,
        recentRecordsSchemeSets: [Int]? = nil,
        recentRecordsShowsBaselines: Bool = SchemaDefaults.recentRecordsShowsBaselines,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.displayUnitRawValue = displayUnit.rawValue
        self.e1RMFormulaRawValue = e1RMFormula.rawValue
        self.displayPrecisionMilliUnits = displayPrecisionMilliUnits
        self.themeRawValue = theme.rawValue
        self.e1RMLookbackDays = e1RMLookbackDays
        self.keepScreenAwake = keepScreenAwake
        self.defaultRoundingIncrementGrams = defaultRoundingIncrementGrams
        self.defaultRoundingStrategyRawValue = defaultRoundingStrategy.rawValue
        self.dashboardExerciseIDs = dashboardExerciseIDs
        self.recentRecordsScopeRawValue = recentRecordsScope.rawValue
        self.recentRecordsExerciseIDs = recentRecordsExerciseIDs
        self.recentRecordsSchemeReps = recentRecordsSchemeReps
        self.recentRecordsSchemeSets = recentRecordsSchemeSets
        self.recentRecordsShowsBaselines = recentRecordsShowsBaselines
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
