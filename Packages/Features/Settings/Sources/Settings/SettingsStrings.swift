import Foundation
import PowerliftingCore
import RepositoryInterface

/// This module's copy (`G-3.4`), and the only place a Settings string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` and binds it to this
/// module's own bundle — a resource in a package resolves against `Bundle.module`, which is
/// per-target and is why every module declares its own accessors rather than sharing one.
/// The key convention itself is documented once, in `Localization`.
enum SettingsStrings {
    /// The unit section's header.
    static let unitsTitle = resource("settings.landing.units.title")

    /// The display-unit picker's label.
    static let unitsPicker = resource("settings.landing.units.picker")

    /// The heading over a preference that could not be written.
    static let writeErrorTitle = resource("settings.landing.write-error.title")

    /// The heading shown when preferences could not be read at all.
    static let loadErrorTitle = resource("settings.landing.load-error.title")

    /// The retry out of the failed phase.
    static let loadErrorRetry = resource("settings.landing.load-error.retry")

    /// The e1RM section's header (`FR-1.7.2`).
    static let estimatorTitle = resource("settings.landing.estimator.title")

    /// The formula picker's label.
    static let estimatorPicker = resource("settings.landing.estimator.picker")

    /// What changing it does — `FR-1.7.3`'s retroactivity, said before it happens.
    static let estimatorDetail = resource("settings.landing.estimator.detail")

    /// What a failed read means, in the user's words rather than the store's.
    static let loadErrorMessage = resource("settings.landing.load-error.message")

    /// The same, for a failed write. `G-3.4`: the error's description is a diagnostic and
    /// never the sentence the user is shown.
    static let writeErrorMessage = resource("settings.landing.write-error.message")

    /// The display-step picker's label (`G-3.3`).
    static let precisionPicker = resource("settings.landing.precision.picker")

    /// The case that is the absence of a choice: the step follows the unit.
    static let precisionAutomatic = resource("settings.landing.precision.automatic")

    /// What the step does, and what it deliberately does not do.
    static let precisionDetail = resource("settings.landing.precision.detail")

    /// The lookback picker's label (`FR-1.7.1`).
    static let lookbackPicker = resource("settings.landing.lookback.picker")

    /// What the window is for.
    static let lookbackDetail = resource("settings.landing.lookback.detail")

    /// The loadable-rounding section's header (`FR-1.5.1.6`).
    static let roundingTitle = resource("settings.landing.rounding.title")

    /// The increment picker's label.
    static let roundingIncrement = resource("settings.landing.rounding.increment")

    /// The direction picker's label.
    static let roundingStrategy = resource("settings.landing.rounding.strategy")

    /// What this rounding is, said against the display step above it.
    static let roundingDetail = resource("settings.landing.rounding.detail")

    /// The appearance section's header (`FR-1.10.2`).
    static let appearanceTitle = resource("settings.landing.appearance.title")

    /// The theme picker's label.
    static let themePicker = resource("settings.landing.appearance.theme")

    /// The accent read-out's label.
    static let accentLabel = resource("settings.landing.appearance.accent")

    /// The one accent there is, named.
    static let accentValue = resource("settings.landing.appearance.accent.value")

    /// Why it is a read-out and not a picker (`G-7.2`).
    static let accentDetail = resource("settings.landing.appearance.accent.detail")

    /// The section over `NFR-1.9`'s toggle.
    static let workoutTitle = resource("settings.landing.workout.title")

    /// The toggle itself.
    static let keepAwakeLabel = resource("settings.landing.workout.keep-awake")

    /// What it does, in the sentence the label has no room for.
    static let keepAwakeHint = resource("settings.landing.workout.keep-awake.hint")

    /// A lookback window, as a number of days.
    ///
    /// - Parameter days: How far back the window reaches.
    /// - Returns: The label.
    static func lookbackDays(_ days: Int) -> LocalizedStringResource {
        resource("settings.landing.lookback.days \(days)")
    }

    /// A rounding direction, as a lifter would describe it.
    ///
    /// - Parameter strategy: The direction to label.
    /// - Returns: Its name.
    static func strategyName(for strategy: RoundingStrategy) -> LocalizedStringResource {
        switch strategy {
        case .nearest: resource("settings.landing.rounding.strategy.nearest")
        case .down: resource("settings.landing.rounding.strategy.down")
        case .up: resource("settings.landing.rounding.strategy.up")
        }
    }

    /// A theme's name (`FR-1.10.2`).
    ///
    /// - Parameter theme: The theme to label.
    /// - Returns: Its name.
    static func themeName(for theme: ThemePreference) -> LocalizedStringResource {
        switch theme {
        case .system: resource("settings.landing.appearance.theme.system")
        case .light: resource("settings.landing.appearance.theme.light")
        case .dark: resource("settings.landing.appearance.theme.dark")
        }
    }

    /// The header over the sections that open another screen.
    static let equipmentTitle = resource("settings.landing.equipment.title")

    /// The header over the section that opens the bodyweight log (`FR-1.8`).
    static let bodyweightSectionTitle = resource("settings.landing.bodyweight.title")

    /// The row into the log. The screen behind it carries its own copy; this names what is there.
    static let bodyweightRow = resource("settings.landing.bodyweight.row")

    /// What is on that screen, in one line.
    static let bodyweightDetail = resource("settings.landing.bodyweight.detail")

    /// The row into the gyms (`FR-1.10.3`). The screen it opens belongs to another module and
    /// carries its own copy; this is the way in, and names what is behind it.
    static let equipmentRow = resource("settings.landing.equipment.row")

    /// What is on that screen, in one line.
    static let equipmentDetail = resource("settings.landing.equipment.detail")

    /// A display unit's abbreviation, as a lifter writes it.
    ///
    /// Copy rather than ICU's: Foundation names `pounds` in full whenever no number is attached.
    ///
    /// - Parameter unit: The unit to label.
    /// - Returns: Its abbreviation.
    static func unitSymbol(for unit: MassUnit) -> LocalizedStringResource {
        switch unit {
        case .kilograms: resource("settings.landing.units.kilograms")
        case .pounds: resource("settings.landing.units.pounds")
        }
    }

    /// A formula's name, as a lifter would see it cited (`FR-1.7.2`).
    ///
    /// - Parameter formula: The formula to label.
    /// - Returns: Its name.
    static func formulaName(for formula: E1RMFormulaID) -> LocalizedStringResource {
        switch formula {
        case .epley: resource("settings.landing.estimator.epley")
        case .brzycki: resource("settings.landing.estimator.brzycki")
        case .lombardi: resource("settings.landing.estimator.lombardi")
        case .oConner: resource("settings.landing.estimator.oconner")
        case .wathan: resource("settings.landing.estimator.wathan")
        case .rpeBased: resource("settings.landing.estimator.rpebased")
        }
    }

    /// Every string this module can show, for the test that proves each one resolves.
    static var all: [LocalizedStringResource] {
        [
            unitsTitle, unitsPicker, writeErrorTitle, writeErrorMessage,
            loadErrorTitle, loadErrorMessage,
            loadErrorRetry, estimatorTitle, estimatorPicker, estimatorDetail,
            precisionPicker, precisionAutomatic, precisionDetail,
            lookbackPicker, lookbackDetail, lookbackDays(90),
            roundingTitle, roundingIncrement, roundingStrategy, roundingDetail,
            appearanceTitle, themePicker, accentLabel, accentValue, accentDetail,
            workoutTitle, keepAwakeLabel, keepAwakeHint,
            equipmentTitle, equipmentRow,
            equipmentDetail, bodyweightSectionTitle, bodyweightRow, bodyweightDetail,
        ] + allBodyweightStrings + allHealthStrings + allAboutStrings + MassUnit.allCases.map(unitSymbol(for:))
            + E1RMFormulaID.allCases.map(formulaName(for:))
            + RoundingStrategy.allCases.map(strategyName(for:))
            + ThemePreference.allCases.map(themeName(for:))
    }

    /// Binds a key to this module's catalogue.
    ///
    /// Internal rather than file-private because `SettingsBodyweightStrings.swift` is the same type
    /// in a second file — see that file for why there is one.
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
