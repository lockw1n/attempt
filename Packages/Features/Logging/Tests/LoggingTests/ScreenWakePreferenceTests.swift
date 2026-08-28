import Foundation
import RepositoryInterface
import Testing

@testable import Logging

/// `NFR-1.9`: the screen stays awake during a workout, and the user can turn that off.
///
/// The value itself lives on the settings row now; what this type still owns is the default it
/// shows before the row is read, the rule that combines it with a workout in progress, and the
/// one-time adoption of the defaults key it used to be stored under.
@Suite("Screen wake preference")
struct ScreenWakePreferenceTests {
    @Test("It is on until the stored row says otherwise")
    func defaultsToOn() {
        #expect(ScreenWakePreference().isEnabled)
        #expect(UserSettings.defaultKeepScreenAwake)
    }

    @Test("It takes the value the row carries, both ways")
    func adoptsTheStoredValue() {
        let preference = ScreenWakePreference()

        preference.adopt(false)
        #expect(!preference.isEnabled)

        preference.adopt(true)
        #expect(preference.isEnabled)
    }

    @Test("The screen is held awake only while both halves hold")
    func bothHalvesAreRequired() {
        let preference = ScreenWakePreference()

        #expect(preference.keepsScreenAwake(duringSession: true))
        // No workout: the preference alone must not keep the screen on while the user browses.
        #expect(!preference.keepsScreenAwake(duringSession: false))

        preference.adopt(false)
        #expect(!preference.keepsScreenAwake(duringSession: true))
        #expect(!preference.keepsScreenAwake(duringSession: false))
    }

    @Test("A key that was never written is nothing to adopt")
    func noLegacyValue() throws {
        // The suite name, not `defaults.description`: the domain is keyed on the former, so cleaning
        // up with the latter removes nothing and leaves a plist behind on every run.
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(ScreenWakePreference.legacyStoredValue(in: defaults) == nil)
    }

    @Test("A stored `false` is read back, rather than being mistaken for an unset key")
    func legacyOffIsRead() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: ScreenWakePreference.legacyKey)

        #expect(ScreenWakePreference.legacyStoredValue(in: defaults) == false)
    }

    @Test("Clearing the key makes the adoption happen once and not on every launch")
    func legacyValueIsCleared() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: ScreenWakePreference.legacyKey)

        ScreenWakePreference.clearLegacyStoredValue(in: defaults)

        #expect(ScreenWakePreference.legacyStoredValue(in: defaults) == nil)
    }
}
