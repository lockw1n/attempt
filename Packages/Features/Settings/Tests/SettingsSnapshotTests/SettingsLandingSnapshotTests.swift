#if os(iOS)

    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Settings

    // TR-1.12 for the Settings landing's link rows (`FR-1.10`–`FR-1.12`). The links rather than the
    // screen, on the preferences suite's terms: the screen is a `.task` over a repository inside a
    // `ScrollView`, and a reference through it is a reference of a spinner in a placeholder.
    //
    // WHY THIS SUITE EXISTS AT ALL, WRITTEN WHERE THE NEXT READER WILL ASK. Until T-1.91's review
    // the landing was the one screen in this module that no reference pictured — `Settings-preferences*`
    // draws `SettingsPreferencesForm`, which is the phase switch's `.loaded` case and nothing below
    // it. That gap was invisible until the rename moved copy that only lives here: "About TotalCraft"
    // and the Health row's detail line are drawn by these rows and by no other screen, so the
    // simulator was the only instrument that could see them. A row's LABEL is also where `G-4.1`'s
    // wrap bites first, and the rename made the longest one three characters longer.
    //
    // NO `NavigationStack` AROUND THESE — the health-access suite beside this one carries the
    // measurement. Every row here is a `NavigationLink`, so these references draw them dimmer than
    // the app does; what they pin is the copy and its layout, and the simulator run is what says the
    // links are live.

    @MainActor
    @Suite("Settings landing snapshots")
    struct SettingsLandingSnapshotTests {
        @Test func links() throws {
            // Every section a lifter meets, on a device that has Health: the recent-PR scope, the
            // gyms, the bodyweight pair, FR-1.11's three files with FR-1.12's sync under them, and
            // About last — the only section here that is about the app rather than about the lifter.
            try assertSnapshots(named: "Settings-landing-links") {
                SettingsLandingLinks(isHealthAvailable: true)
            }
        }

        @Test func linksWithoutHealth() throws {
            // FR-1.10.4's row is ABSENT rather than dimmed where this device has no health source
            // (T-1.51's rule). This is the reference that says so: the bodyweight section is one row
            // here and two above, and nothing else on the screen moves.
            try assertSnapshots(named: "Settings-landing-links-no-health") {
                SettingsLandingLinks(isHealthAvailable: false)
            }
        }
    }

#endif
