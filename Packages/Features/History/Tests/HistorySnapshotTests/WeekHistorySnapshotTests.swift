#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import History

    // TR-1.12 for `FR-17.11`'s week view, on the same terms as every other screen's references: the
    // pieces are rendered rather than the screen, because a screen builds its own state over three
    // repositories and a reference must not need one.
    //
    // EVERY REFERENCE HERE PINS ITS LOCALE, ITS CALENDAR AND ITS TIME ZONE. The locale for the
    // session list's reason (a grouped number is written differently by region); the calendar
    // because the heading's two ends are rendered through `AppFormat.resolved(_:in:)`, which binds
    // to it; and the zone because a ROW's day still goes through `Text(_:format:)`, which resolves
    // its own out of the environment.

    @MainActor
    @Suite("Week history snapshots")
    struct WeekHistorySnapshotTests {
        @Test func weekRows() throws {
            // FR-17.11.1's block: the date range as the heading, and one row per day trained. The
            // two rows in the newest week are the picture the requirement is actually about — a day
            // inside a program says its position, a day outside one says **Free workout**, and the
            // log's own rows say neither.
            try assertSnapshots(named: "Week-history-rows") {
                WeekFixtures.list()
            }
        }

        @Test func markedDay() throws {
            // FR-17.11.2's day, opened from the calendar. THREE SIGNALS, NONE OF THEM COLOUR
            // (`G-4.5`): the ring this pictures, the inset that makes room for it, and a VoiceOver
            // trait no image can hold. A stroke rather than a fill, so it spends none of
            // `FR-16.6.4`'s one accent.
            try assertSnapshots(named: "Week-history-marked-day") {
                WeekFixtures.list(marking: WeekFixtures.day(9))
            }
        }

        @Test func nothingLoggedYet() throws {
            // The tab's week mode on a first launch: the control the user chose, above the reason
            // there is nothing under it. The control stays, because the mode is still a choice —
            // an empty state that swallowed it would strand the reader in the mode they picked.
            try assertSnapshots(named: "Week-history-empty") {
                WeekFixtures.empty()
            }
        }
    }

    /// What these references render.
    enum WeekFixtures {
        /// The locale every reference here is recorded in.
        static let locale = Locale(identifier: "en_US")

        /// The calendar every reference here is recorded in: Gregorian, UTC, Sunday-first.
        static var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            calendar.firstWeekday = 1
            calendar.locale = locale
            return calendar
        }

        /// The weeks every reference here draws: the week of 4 January 2026 with two days in it,
        /// and the week before it with one.
        ///
        /// **The older week is what makes the heading's year readable as a range rather than as a
        /// date**: it begins in December and ends in January, which is the straddle `FR-17.11.3`
        /// says a program week can make and the calendar week always can.
        static var weeks: [HistoryWeekSection] {
            [
                HistoryWeekSection(
                    start: day(4),
                    end: day(10),
                    summaries: [
                        summary(
                            "A001",
                            on: day(9),
                            names: ["Back Squat", "Bench Press"],
                            sets: 8,
                            kilograms: 7_240,
                            position: ProgramPosition(week: 3, day: 2)
                        ),
                        summary(
                            "A002", on: day(6), names: ["Deadlift"], sets: 5, kilograms: 4_100
                        ),
                    ]
                ),
                HistoryWeekSection(
                    start: day(-3),
                    end: day(3),
                    summaries: [
                        summary(
                            "A003",
                            on: day(2),
                            names: ["Overhead Press", "Barbell Row"],
                            sets: 9,
                            kilograms: 3_860,
                            position: ProgramPosition(week: 2, day: 4)
                        )
                    ]
                ),
            ]
        }

        /// The list itself.
        ///
        /// - Parameter marking: The day the screen was opened on, or `nil`.
        /// - Returns: The list.
        static func list(marking marked: Date? = nil) -> some View {
            WeekHistoryList(weeks: weeks, unit: .kilograms, markedDay: marked)
                .environment(\.locale, locale)
                .environment(\.calendar, calendar)
                .environment(\.timeZone, .gmt)
        }

        /// The tab's week mode with nothing logged: the control, and the state under it.
        ///
        /// Composed the way ``SessionListView`` composes them rather than rendered through it — the
        /// screen holds three states over three repositories, and the control is its own view so
        /// that this half is production code and not a second drawing of it.
        static func empty() -> some View {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                HistoryModeControl(mode: .constant(.weeks))
                EmptyStateView(
                    symbolName: "calendar",
                    headline: Text(HistoryStrings.weekEmptyHeadline),
                    message: Text(HistoryStrings.weekEmptyMessage),
                    action: StateAction(Text(HistoryStrings.weekEmptyAction), emphasis: .primary) {}
                )
            }
            .environment(\.locale, locale)
        }

        /// A day of January 2026, as its first instant — a non-positive number reaching back into
        /// the December before it.
        ///
        /// - Parameter number: The day of the month.
        /// - Returns: The instant.
        static func day(_ number: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 1, day: number))
                ?? Date(timeIntervalSince1970: 0)
        }

        /// One row.
        private static func summary(
            _ suffix: String,
            on date: Date,
            names: [String],
            sets: Int,
            kilograms: Int,
            position: ProgramPosition? = nil
        ) -> SessionSummary {
            SessionSummary(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000\(suffix)") ?? UUID(),
                date: date,
                exerciseNames: names,
                setCount: sets,
                tonnage: Weight(grams: kilograms * 1_000),
                notes: "",
                programPosition: position
            )
        }
    }

#endif
