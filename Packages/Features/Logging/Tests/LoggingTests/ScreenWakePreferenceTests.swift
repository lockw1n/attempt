import Foundation
import Logging
import Testing

/// `NFR-1.9`: the screen stays awake during a workout, and the user can turn that off.
///
/// Each test gets its own defaults suite, because the preference outlives a process on purpose and a
/// shared suite would let one test's choice decide the next one's.
@Suite("Screen wake preference")
struct ScreenWakePreferenceTests {
    @Test("It is on until the user says otherwise")
    func defaultsToOn() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        #expect(ScreenWakePreference(defaults: defaults).isEnabled)
    }

    @Test("A stored `false` is read back, rather than being mistaken for an unset key")
    func storedOffIsRead() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "logging.screen-wake.enabled")

        #expect(!ScreenWakePreference(defaults: defaults).isEnabled)
    }

    @Test("The user's choice survives the process it was made in")
    func choiceIsPersisted() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = ScreenWakePreference(defaults: defaults)

        preference.setEnabled(false)

        #expect(!preference.isEnabled)
        // A second instance over the same storage is what the next launch has.
        #expect(!ScreenWakePreference(defaults: defaults).isEnabled)
    }

    @Test("Turning it back on is stored too")
    func choiceIsReversible() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = ScreenWakePreference(defaults: defaults)
        preference.setEnabled(false)

        preference.setEnabled(true)

        #expect(ScreenWakePreference(defaults: defaults).isEnabled)
    }

    @Test("The screen is held awake only while both halves hold")
    func bothHalvesAreRequired() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = ScreenWakePreference(defaults: defaults)

        #expect(preference.keepsScreenAwake(duringSession: true))
        // No workout: the preference alone must not keep the screen on while the user browses.
        #expect(!preference.keepsScreenAwake(duringSession: false))

        preference.setEnabled(false)
        #expect(!preference.keepsScreenAwake(duringSession: true))
        #expect(!preference.keepsScreenAwake(duringSession: false))
    }
}
