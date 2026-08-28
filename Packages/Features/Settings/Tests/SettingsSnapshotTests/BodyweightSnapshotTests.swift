#if os(iOS)

    import Foundation
    import PowerliftingCore
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Settings

    // TR-1.12 for FR-1.8.1 and FR-1.8.3. The reading rather than the screen, on the dashboard
    // suite's terms: the screen is a `.task` over two repositories, and a reference through it is a
    // reference of a spinner.
    //
    // THE REFERENCES PIN THEIR LOCALE AND THEIR TIME ZONE — every row renders a day and a load.

    @MainActor
    @Suite("Bodyweight snapshots")
    struct BodyweightSnapshotTests {
        @Test func log() throws {
            // The whole screen in one picture: today's average over a history whose oldest row has
            // no window of its own to average. The absent line on that row IS the assertion.
            try assertSnapshots(named: "Bodyweight-log") {
                BodyweightLogReading(
                    state: .ready(BodyweightFixtures.readings),
                    currentAverage: Weight(grams: 82_333),
                    unit: .kilograms,
                    writeFailure: nil,
                    healthImport: nil,
                    retry: {},
                    add: {},
                    importFromHealth: {}
                )
                .environment(\.locale, BodyweightFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func averageInsufficient() throws {
            // FR-1.13.3's whole point, pictured: what the card draws INSTEAD OF a single reading
            // presented as a week's average.
            try assertSnapshots(named: "Bodyweight-average-none") {
                BodyweightLogReading(
                    state: .ready(Array(BodyweightFixtures.readings.prefix(1))),
                    currentAverage: nil,
                    unit: .kilograms,
                    writeFailure: nil,
                    healthImport: nil,
                    retry: {},
                    add: {},
                    importFromHealth: {}
                )
                .environment(\.locale, BodyweightFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func empty() throws {
            // FR-1.13.2's first launch: the action that makes the first reading is the state's own.
            try assertSnapshots(named: "Bodyweight-empty") {
                BodyweightLogReading(
                    state: .empty,
                    currentAverage: nil,
                    unit: .kilograms,
                    writeFailure: nil,
                    healthImport: nil,
                    retry: {},
                    add: {},
                    importFromHealth: {}
                )
            }
        }

        @Test func unreadable() throws {
            try assertSnapshots(named: "Bodyweight-error") {
                BodyweightLogReading(
                    state: .failed,
                    currentAverage: nil,
                    unit: .kilograms,
                    writeFailure: nil,
                    healthImport: nil,
                    retry: {},
                    add: {},
                    importFromHealth: {}
                )
            }
        }

        @Test func writeFailed() throws {
            // A failed save above a list that is still there — the diagnostic never replaces the
            // log it was written against.
            try assertSnapshots(named: "Bodyweight-write-error") {
                BodyweightLogReading(
                    state: .ready(Array(BodyweightFixtures.readings.prefix(2))),
                    currentAverage: Weight(grams: 83_000),
                    unit: .pounds,
                    writeFailure: "recordNotFound(id: 5A5B0000-0000-4000-8000-000000000001)",
                    healthImport: nil,
                    retry: {},
                    add: {},
                    importFromHealth: {}
                )
                .environment(\.locale, BodyweightFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func healthImport() throws {
            // FR-1.8.2's command with a finished import under it: the two counts are the whole
            // outcome, and the detail line is where G-5.4 is said to the user rather than only in
            // the system prompt.
            try assertSnapshots(named: "Bodyweight-health-import") {
                BodyweightLogReading(
                    state: .ready(Array(BodyweightFixtures.readings.prefix(2))),
                    currentAverage: Weight(grams: 83_000),
                    unit: .kilograms,
                    writeFailure: nil,
                    healthImport: .imported(added: 2, daysAlreadyEntered: 1),
                    retry: {},
                    add: {},
                    importFromHealth: {}
                )
                .environment(\.locale, BodyweightFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func healthImportRunning() throws {
            // FR-1.13.1: the import in flight draws T-1.09's LoadingStateView over a log that is
            // still there, which is the read that component's own doc comment was written for.
            try assertSnapshots(named: "Bodyweight-health-running") {
                BodyweightLogReading(
                    state: .ready(Array(BodyweightFixtures.readings.prefix(1))),
                    currentAverage: nil,
                    unit: .kilograms,
                    writeFailure: nil,
                    healthImport: .importing,
                    retry: {},
                    add: {},
                    importFromHealth: {}
                )
                .environment(\.locale, BodyweightFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func healthImportFailed() throws {
            // A failed import above a log that is still there — the write failure's rule, and the
            // command stays offered because a retry is the only way out of it.
            try assertSnapshots(named: "Bodyweight-health-error") {
                BodyweightLogReading(
                    state: .ready(Array(BodyweightFixtures.readings.prefix(1))),
                    currentAverage: nil,
                    unit: .kilograms,
                    writeFailure: nil,
                    healthImport: .failed("authorizationNotDetermined"),
                    retry: {},
                    add: {},
                    importFromHealth: {}
                )
                .environment(\.locale, BodyweightFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func form() throws {
            // FR-1.8.1's two fields, without the sheet around them: `ImageRenderer` draws none of a
            // `ScrollView`'s content.
            //
            // THE FIELD AND THE PICKER THEMSELVES DRAW AS THE RENDERER'S PLACEHOLDER — both are
            // UIKit-backed, which the harness documents. What this reference pins is the labels,
            // the unit beside the field and the hint under the picker; what the controls look like
            // is the simulator run's.
            try assertSnapshots(named: "Bodyweight-form") {
                BodyweightFormPreview()
                    .environment(\.locale, BodyweightFixtures.locale)
                    .environment(\.timeZone, .gmt)
            }
        }
    }

    /// The form over a draft that does not move, so the reference does not either.
    private struct BodyweightFormPreview: View {
        @State private var draft = BodyweightEntryDraft(
            unit: .kilograms,
            locale: BodyweightFixtures.locale,
            calendar: BodyweightFixtures.calendar,
            day: BodyweightFixtures.day,
            newEntryID: BodyweightFixtures.formID
        )

        var body: some View {
            BodyweightEntryFormContent(draft: $draft, unit: .kilograms)
        }
    }

    /// What these references render.
    enum BodyweightFixtures {
        /// Pinned because a Mac's region is not its language.
        static let locale = Locale(identifier: "en_US")

        /// Every date here is GMT, so a reference committed in one time zone matches in another.
        static var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            return calendar
        }

        /// The day everything is dated from, fixed so a reference committed today still matches
        /// next year.
        static let day = Date(timeIntervalSince1970: 1_700_000_000)

        /// The identity the form's draft takes, so it is not minted afresh on every render.
        static let formID =
            UUID(uuidString: "B0DE0000-0000-4000-8000-000000000099") ?? UUID()

        /// Three readings, newest first, the oldest with no window of its own.
        static let readings: [BodyweightReading] = [
            reading(index: 1, daysAgo: 0, grams: 84_000, average: Weight(grams: 82_333)),
            reading(index: 2, daysAgo: 3, grams: 82_000, average: Weight(grams: 81_000)),
            reading(index: 3, daysAgo: 9, grams: 80_000, average: nil),
        ]

        /// One row.
        private static func reading(
            index: Int, daysAgo: Int, grams: Int, average: Weight?
        ) -> BodyweightReading {
            BodyweightReading(
                id: UUID(uuidString: "B0DE0000-0000-4000-8000-0000000000\(index)0") ?? UUID(),
                date: day.addingTimeInterval(-Double(daysAgo) * 86_400),
                weight: Weight(grams: grams),
                average: average
            )
        }
    }

#endif
