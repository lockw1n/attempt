import Foundation
import PowerliftingCore

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

    /// The heading over the read-outs that are not preferences yet.
    static let scaffoldTitle = resource("settings.landing.scaffold.title")

    /// The appearance read-out's label.
    static let scaffoldAppearance = resource("settings.landing.scaffold.appearance")

    /// The header over the sections that open another screen.
    static let equipmentTitle = resource("settings.landing.equipment.title")

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
            unitsTitle, unitsPicker, writeErrorTitle, loadErrorTitle, loadErrorRetry,
            estimatorTitle, estimatorPicker, estimatorDetail,
            scaffoldTitle, scaffoldAppearance, equipmentTitle, equipmentRow,
            equipmentDetail,
        ] + MassUnit.allCases.map(unitSymbol(for:))
            + E1RMFormulaID.allCases.map(formulaName(for:))
    }

    /// Binds a key to this module's catalogue.
    private static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
