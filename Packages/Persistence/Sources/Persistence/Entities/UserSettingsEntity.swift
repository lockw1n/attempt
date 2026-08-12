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

    /// ``ThemePreference``'s raw value (`FR-1.10.2`).
    var themeRawValue: String = SchemaDefaults.theme

    /// The loadable step new exercises get by default, in grams (`FR-1.5.1.6`).
    ///
    /// Unvalidated: a value below one gram maps to no `RoundingRule`, and the refusal is the
    /// mapping's rather than this column's.
    var defaultRoundingIncrementGrams: Int = SchemaDefaults.roundingIncrementGrams

    /// ``PowerliftingCore/RoundingStrategy``'s raw value, the direction half of the same default.
    var defaultRoundingStrategyRawValue: String = SchemaDefaults.roundingStrategy

    init(
        id: UUID = UUID(),
        userID: UUID,
        displayUnit: MassUnit,
        e1RMFormula: E1RMFormulaID,
        theme: ThemePreference,
        defaultRoundingIncrementGrams: Int,
        defaultRoundingStrategy: RoundingStrategy,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.displayUnitRawValue = displayUnit.rawValue
        self.e1RMFormulaRawValue = e1RMFormula.rawValue
        self.themeRawValue = theme.rawValue
        self.defaultRoundingIncrementGrams = defaultRoundingIncrementGrams
        self.defaultRoundingStrategyRawValue = defaultRoundingStrategy.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
