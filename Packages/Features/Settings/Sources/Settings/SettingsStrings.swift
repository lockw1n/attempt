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

    /// The heading over the read-outs that are not preferences yet.
    static let scaffoldTitle = resource("settings.landing.scaffold.title")

    /// The estimator read-out's label.
    static let scaffoldEstimator = resource("settings.landing.scaffold.estimator")

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

    /// Every string this module can show, for the test that proves each one resolves.
    static var all: [LocalizedStringResource] {
        [
            unitsTitle, unitsPicker, writeErrorTitle, loadErrorTitle, loadErrorRetry,
            scaffoldTitle, scaffoldEstimator, scaffoldAppearance, equipmentTitle, equipmentRow,
            equipmentDetail,
        ] + MassUnit.allCases.map(unitSymbol(for:))
    }

    /// Binds a key to this module's catalogue.
    private static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
