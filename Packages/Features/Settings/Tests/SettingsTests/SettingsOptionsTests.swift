import PowerliftingCore
import Testing

@testable import Settings

/// What the pickers offer (`G-3.3`, `FR-1.5.1.6`, `FR-1.7.1`).
@Suite("Settings options")
struct SettingsOptionsTests {
    @Test("The display steps are the four common ones, finest first")
    func displayStepsAreOffered() {
        #expect(
            SettingsOptions.displayPrecisions(including: nil).map(\.milliUnits)
                == [100, 250, 500, 1_000])
    }

    /// A picker whose selection is absent from its own options draws no selection at all, so the
    /// next tap would silently replace a setting the user came to read.
    @Test("A step the app would not have offered is still offered, in its place")
    func anUnusualStepJoinsTheList() throws {
        let stored = try #require(DisplayPrecision(milliUnits: 200))

        #expect(
            SettingsOptions.displayPrecisions(including: stored).map(\.milliUnits)
                == [100, 200, 250, 500, 1_000])
    }

    @Test("A step already in the list is not offered twice")
    func aKnownStepIsNotDuplicated() {
        #expect(SettingsOptions.displayPrecisions(including: .half).count == 4)
    }

    /// The increments are the plates a gym owns, which come in the unit its lifters count in —
    /// 2.5 kg is 5.51 lb, so a pound list of kilogram steps offers nobody a step they have.
    @Test("Kilogram and pound increments are different masses")
    func incrementsFollowTheUnit() {
        let kilograms = SettingsOptions.roundingIncrements(
            for: .kilograms, including: Weight(grams: 2500))
        let pounds = SettingsOptions.roundingIncrements(
            for: .pounds, including: Weight(grams: 2268))

        #expect(kilograms.map(\.grams) == [500, 1_000, 1_250, 2_500, 5_000])
        #expect(pounds.map(\.grams) == [454, 1_134, 2_268, 4_536])
    }

    @Test("An increment from the other unit is kept, in its place")
    func aForeignIncrementJoinsTheList() {
        let offered = SettingsOptions.roundingIncrements(
            for: .pounds, including: Weight(grams: 2500))

        #expect(offered.map(\.grams) == [454, 1_134, 2_268, 2_500, 4_536])
    }

    @Test("The lookback windows are the five common ones")
    func lookbackWindowsAreOffered() {
        #expect(SettingsOptions.lookbackWindows(including: 90) == [30, 60, 90, 180, 365])
    }

    @Test("A window the app would not have offered is still offered, in its place")
    func anUnusualWindowJoinsTheList() {
        #expect(SettingsOptions.lookbackWindows(including: 45) == [30, 45, 60, 90, 180, 365])
    }
}
