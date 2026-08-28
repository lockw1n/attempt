#if os(iOS)

    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Settings

    // TR-1.12 for FR-1.10.1 and FR-1.10.2. The form rather than the screen, on the bodyweight
    // suite's terms: the screen is a `.task` over a repository, and a reference through it is a
    // reference of a spinner.
    //
    // THE REFERENCES PIN THEIR LOCALE — every picker below draws a step or an increment as a mass.
    //
    // WHAT THEY DO NOT PIN IS THE CONTROLS. `Picker` and `Toggle` are UIKit-backed and do not
    // rasterise, so each is drawn as the renderer's placeholder — the same limitation the logging
    // suite records. What these check is that the labels and their sentences stay legible beside a
    // row of control-sized holes, which is where `NFR-1.10`'s ceiling bites.

    @MainActor
    @Suite("Settings preferences snapshots")
    struct SettingsPreferencesSnapshotTests {
        @Test func defaults() throws {
            // What a lifter who has configured nothing sees: kilograms, the automatic step, and
            // NFR-1.9's toggle on.
            try assertSnapshots(named: "Settings-preferences") {
                SettingsPreferencesForm(
                    settings: SettingsSnapshotFixtures.row, writeFailure: nil, apply: { _ in }
                )
                .environment(\.locale, SettingsSnapshotFixtures.locale)
            }
        }

        @Test func configured() throws {
            // Every control off its default, and the pound increments the unit switch brings with
            // it — the list is not the kilogram one converted.
            var configured = SettingsSnapshotFixtures.row
            configured.displayUnit = .pounds
            configured.displayPrecision = .tenth
            configured.e1RMFormula = .wathan
            configured.e1RMLookbackDays = 30
            configured.theme = .light
            configured.keepScreenAwake = false
            configured.defaultRoundingIncrement = Weight(grams: 2268)
            configured.defaultRoundingStrategy = .down

            try assertSnapshots(named: "Settings-preferences-configured") {
                SettingsPreferencesForm(settings: configured, writeFailure: nil, apply: { _ in })
                    .environment(\.locale, SettingsSnapshotFixtures.locale)
            }
        }

        @Test func writeFailed() throws {
            // The failed write sits ABOVE the controls rather than replacing them: the row is still
            // loaded and still editable, so the retry is the next tap.
            try assertSnapshots(named: "Settings-preferences-write-failed") {
                SettingsPreferencesForm(
                    settings: SettingsSnapshotFixtures.row,
                    writeFailure: "identityAlreadyEstablished(recordID: …)",
                    apply: { _ in }
                )
                .environment(\.locale, SettingsSnapshotFixtures.locale)
            }
        }
    }

    /// The one row these references are drawn from.
    enum SettingsSnapshotFixtures {
        /// Pinned, for the steps and increments the pickers draw as masses.
        static let locale = Locale(identifier: "en_GB")

        /// A settings row at its first-launch values.
        static var row: UserSettings {
            let stamp = Date(timeIntervalSince1970: 1_700_000_000)
            return UserSettings(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                userID: UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID(),
                displayUnit: .kilograms,
                e1RMFormula: .epley,
                theme: .dark,
                defaultRoundingIncrement: Weight(grams: 2500),
                defaultRoundingStrategy: .nearest)
        }
    }

#endif
