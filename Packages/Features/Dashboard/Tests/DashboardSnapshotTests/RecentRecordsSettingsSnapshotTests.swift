#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Dashboard

    // TR-1.12 for FR-16.3's configuration and for FR-16.3.4's offer, on the settings suite's terms:
    // the form rather than the screen, because the screen is a `.task` over two repositories and a
    // reference through it is a reference of a spinner.
    //
    // WHAT THEY DO NOT PIN IS THE CONTROLS. `Picker` and `Toggle` are UIKit-backed and do not
    // rasterise, so each is drawn as the renderer's placeholder. What these check is that the
    // headings and their sentences stay legible beside a row of control-sized holes, which is where
    // `NFR-1.10`'s ceiling bites — and, on the offer, that a button under an insufficient-data
    // message still reads as the next tap at the largest size.

    @MainActor
    @Suite("Recent PRs configuration snapshots")
    struct RecentRecordsSettingsSnapshotTests {
        @Test func defaults() throws {
            // What a lifter who has configured nothing sees: the dashboard scope, every scheme,
            // baselines off — and therefore neither the Choose lifts row nor the scheme list.
            try assertSnapshots(named: "RecentRecords-settings") {
                RecentRecordsSettingsForm(
                    settings: SettingsFixtures.row,
                    chosenExerciseCount: 0,
                    schemes: SettingsFixtures.schemes,
                    hasFailedWrite: false,
                    apply: { _ in },
                    setSchemesChosen: { _ in },
                    toggleScheme: { _ in })
            }
        }

        @Test func chosenScopeAndSchemes() throws {
            // The chosen scope and the chosen schemes together: `FR-17.3.3`'s row carrying its
            // count, and the scheme list the toggle above it reveals.
            //
            // THE COUNT IS READ OFF THE SAME ROW THE SCREEN READS IT FROM, not passed as a number
            // this fixture chose: production computes it from `recentRecordsExerciseIDs`, and a
            // fixture picking its own would picture a row that cannot happen.
            var configured = SettingsFixtures.row
            configured.recentRecordsScope = .chosen
            configured.recentRecordsExerciseIDs = SettingsFixtures.exercises.map(\.exerciseID)
            configured.recentRecordsSchemes = .chosen([RecordScheme(reps: 5, sets: 5)])
            configured.recentRecordsShowsBaselines = true

            try assertSnapshots(named: "RecentRecords-settings-chosen") {
                RecentRecordsSettingsForm(
                    settings: configured,
                    chosenExerciseCount: configured.recentRecordsExerciseIDs?.count ?? 0,
                    schemes: SettingsFixtures.chosenSchemes,
                    hasFailedWrite: false,
                    apply: { _ in },
                    setSchemesChosen: { _ in },
                    toggleScheme: { _ in }
                )
            }
        }

        @Test func pushedLiftPicker() throws {
            // FR-17.3.3's own screen: the list that used to unfold inside the form above.
            //
            // THE LOCALE AND THE TIME ZONE ARE PINNED, and only here: this is the one reference in
            // the suite that renders a date — `FR-16.5.3`'s "last trained" under a chosen lift —
            // and `SnapshotHarness` pins neither itself. Unpinned, the day 1_700_000_000 falls on
            // moves east of UTC+2 and the format moves with the recording machine's own locale.
            try assertSnapshots(named: "RecentRecords-exercises") {
                RecentRecordsExercisesReading(
                    state: .ready(SettingsFixtures.exerciseSections),
                    searchText: .constant(""),
                    hasFailedWrite: false,
                    retry: {},
                    toggle: { _ in }
                )
                .environment(\.locale, SettingsFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func nothingInScope() throws {
            // FR-16.3.4's offer: the empty feed under a narrower scope, with the widening as a
            // button rather than a sentence pointing at Settings.
            try assertSnapshots(named: "RecentRecords-none-in-scope") {
                InsufficientDataView(
                    message: Text(DashboardStrings.recentRecordsNoneInScope),
                    action: StateAction(
                        Text(DashboardStrings.recentRecordsShowEverything),
                        emphasis: .secondary,
                        handler: {}))
            }
        }
    }

    /// What these references render: an unconfigured row, two exercises and two schemes.
    enum SettingsFixtures {
        /// A settings row at every shipped default, so `defaults()` pictures what ships.
        static let row = UserSettings(
            id: UUID(uuidString: "1E7C0000-0000-0000-0000-000000000001") ?? UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            userID: UUID(uuidString: "1E7C0000-0000-0000-0000-000000000002") ?? UUID(),
            displayUnit: .kilograms,
            e1RMFormula: .epley,
            theme: .system,
            defaultRoundingIncrement: Weight(grams: 2500),
            defaultRoundingStrategy: .nearest)

        /// One ticked and one not, so a row's two states are in one picture — and one trained and
        /// one untrained, so the `.chosen` list draws both of `FR-16.5.3`'s
        /// sections and the date under a name is in the picture.
        static let exercises = [
            TiledExerciseChoice(
                exerciseID: UUID(), name: "Back Squat", isTiled: true, lastTrained: trainedDay),
            TiledExerciseChoice(
                exerciseID: UUID(), name: "Triceps Kickback", isTiled: false, lastTrained: nil),
        ]

        /// The day the trained row was last performed. Fixed, so a reference committed today still
        /// matches next year — and rendered against ``locale`` and GMT, so it matches on another
        /// machine too.
        static let trainedDay = Date(timeIntervalSince1970: 1_700_000_000)

        /// The locale that day is rendered in. Every dated reference in this package pins one; the
        /// harness does not.
        static let locale = Locale(identifier: "en_US")

        /// Those rows as the screen draws them (`FR-16.5.3`).
        static let exerciseSections = ExerciseChoiceSections.sections(exercises, matching: "")

        /// The un-narrowed case: cells the log offers, none of them the lifter's own choice.
        static let schemes = [
            RecentRecordsSchemeChoice(scheme: RecordScheme(reps: 5, sets: 5), isChosen: false),
            RecentRecordsSchemeChoice(scheme: RecordScheme(reps: 3, sets: 1), isChosen: false),
        ]

        /// The chosen case: the same cells with one of them ticked.
        static let chosenSchemes = [
            RecentRecordsSchemeChoice(scheme: RecordScheme(reps: 5, sets: 5), isChosen: true),
            RecentRecordsSchemeChoice(scheme: RecordScheme(reps: 3, sets: 1), isChosen: false),
        ]
    }

#endif
