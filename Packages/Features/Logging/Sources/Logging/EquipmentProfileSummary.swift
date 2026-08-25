import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface

/// One gym in words, for the row that stands for it in a list (`FR-1.4.3`, `FR-1.10.3`).
///
/// **A type of its own rather than a method on the view**, for the reason every other formatting
/// helper in this module has one: what a summary says is a unit test's question, where what it looks
/// like is a snapshot's.
enum EquipmentProfileSummary {
    /// What the gym stocks, as one line.
    ///
    /// **A stored profile is summarised by zipping its two lists**, which is the same tolerance
    /// `EquipmentProfile.inventory()`'s refusal is written for: a row whose lists disagree in length
    /// still has to be listed, or the screen that repairs it could not be reached.
    ///
    /// An empty inventory is **not** an empty string: a gym with no plates is a real profile that
    /// loads exactly one weight, and a blank line would read as a failure to describe it.
    ///
    /// - Parameters:
    ///   - profile: The gym.
    ///   - unit: The unit the denominations are drawn in (`G-3.1`).
    ///   - locale: What the numbers and the list separator are rendered for (`G-3.4`).
    /// - Returns: The line.
    static func plates(of profile: EquipmentProfile, unit: MassUnit, locale: Locale) -> String {
        let items = zip(profile.plates, profile.platePairCounts).map { plate, pairs in
            String(
                localized: LoggingStrings.equipmentPlatePairs(
                    plate: PlateLoadingSummary.render(plate, in: unit, locale: locale),
                    pairs: pairs
                ))
        }
        guard !items.isEmpty else { return String(localized: LoggingStrings.equipmentNoPlates) }
        return items.formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    /// The bar and its collars — the half of a profile a plate list does not show.
    ///
    /// The collar is drawn as **one** collar, matching both the stored column and the field that
    /// wrote it: a summary that showed the pair would make the same factor-of-two error invisible
    /// from the other end.
    ///
    /// - Parameters:
    ///   - profile: The gym.
    ///   - unit: The unit the masses are drawn in (`G-3.1`).
    ///   - locale: What the numbers are rendered for (`G-3.4`).
    /// - Returns: The line.
    static func bar(
        of profile: EquipmentProfile,
        unit: MassUnit,
        locale: Locale
    ) -> LocalizedStringResource {
        LoggingStrings.plateEquipmentBar(
            bar: PlateLoadingSummary.render(profile.barWeight, in: unit, locale: locale),
            collar: PlateLoadingSummary.render(profile.collarWeight, in: unit, locale: locale)
        )
    }

    /// What to call a gym in a list — the user's name for it, or the stand-in for one left unnamed.
    ///
    /// The same answer ``LoadedEquipment/displayName`` gives, and deliberately the same string: a
    /// gym must not be called one thing on the calculator and another on the screen that named it.
    ///
    /// - Parameter profile: The gym.
    /// - Returns: Its name.
    static func name(of profile: EquipmentProfile) -> String {
        profile.name.isEmpty
            ? String(localized: LoggingStrings.plateEquipmentUnnamed)
            : profile.name
    }
}
