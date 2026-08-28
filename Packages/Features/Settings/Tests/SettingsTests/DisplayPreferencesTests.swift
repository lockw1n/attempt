import DesignSystem
import PowerliftingCore
import RepositoryInterface
import SwiftUI
import Testing

@testable import Settings

/// `FR-1.10.2`'s theme and `G-3.3`'s step, as the app holds them between screens.
@MainActor
@Suite("Display preferences")
struct DisplayPreferencesTests {
    /// The difference the type exists for: an unread row is `G-7.1`'s dark, and a row saying
    /// *system* is the device's choice. Collapsing the two makes a fresh install follow the device.
    @Test("An unread row is dark; a stored `system` follows the device")
    func unreadIsNotSystem() {
        #expect(DisplayPreferences().colorScheme == Appearance.defaultColorScheme)

        let read = DisplayPreferences()
        read.adopt(row(theme: .system))
        #expect(read.colorScheme == nil)
    }

    @Test("Light and dark are taken as written")
    func explicitThemesAreHonoured() {
        let preferences = DisplayPreferences()

        preferences.adopt(row(theme: .light))
        #expect(preferences.colorScheme == .light)

        preferences.adopt(row(theme: .dark))
        #expect(preferences.colorScheme == .dark)
    }

    @Test("The step comes off the row, and an unchosen one stays absent")
    func stepIsAdopted() {
        let preferences = DisplayPreferences()

        preferences.adopt(row(precision: .quarter))
        #expect(preferences.weightPrecision == .quarter)

        preferences.adopt(row(precision: nil))
        #expect(preferences.weightPrecision == nil)
    }

    /// `nil` is the absence of a step and not a step, so a screen resolves it against the unit —
    /// which is the whole reason the column is optional.
    @Test("An absent step resolves to the unit's own")
    func absentStepResolvesToTheUnit() {
        #expect(WeightDisplay(unit: .kilograms, resolving: nil).precision == .half)
        #expect(WeightDisplay(unit: .pounds, resolving: nil).precision == .whole)
        #expect(WeightDisplay(unit: .pounds, resolving: .quarter).precision == .quarter)
    }
}

/// A settings row carrying the two display preferences under test.
///
/// - Parameters:
///   - theme: The stored theme.
///   - precision: The stored step, or `nil` where the unit's own stands.
/// - Returns: The row.
private func row(
    theme: ThemePreference = .dark, precision: DisplayPrecision? = nil
) -> UserSettings {
    var row = UserSettings.fixture()
    row.theme = theme
    row.displayPrecision = precision
    return row
}
