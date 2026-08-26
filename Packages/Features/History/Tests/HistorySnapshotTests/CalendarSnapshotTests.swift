#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import History

    // TR-1.12 for the calendar (`FR-1.5.3`), on the same terms as the session list's references: the
    // pieces are rendered rather than the screen, because a screen builds its own state over a
    // repository and a reference must not need one.
    //
    // EVERY REFERENCE HERE PINS BOTH ITS LOCALE AND ITS CALENDAR. The locale for the reason the
    // session list's file gives, and the calendar for the same reason one level along: `Calendar`
    // decides the first weekday and the time zone, so a Mac set to a Monday-first region would
    // record a grid a Sunday-first Mac cannot match — and every cell would be in the wrong column
    // rather than one pixel out, which is the kind of diff that reads as a real regression.
    //
    // THE GRID CLAMPS DYNAMIC TYPE AT `accessibility1`, and the `accessibility3` reference is where
    // that is visible. It is the one deliberate clamp in this app: seven columns cannot reflow into
    // a stack without ceasing to be a calendar. What the same reference also has to show is that
    // nothing *under* the grid is clamped — see the day section's own images.

    @MainActor
    @Suite("Calendar snapshots")
    struct CalendarSnapshotTests {
        @Test func monthGrid() throws {
            // January 2026: it starts on a Thursday, so the first week is four padding cells, and
            // it needs five rows. The marked days include the first and the last of the month,
            // which are the two a leading- or trailing-padding error moves.
            try assertSnapshots(named: "Calendar-grid") {
                CalendarFixtures.grid()
            }
        }

        @Test func monthGridWithNothingMarked() throws {
            // A month off. Not the empty *state* — the grid is right, and a month with no training
            // in it is a fact a lifter wants to see rather than an apology.
            try assertSnapshots(named: "Calendar-grid-untrained") {
                CalendarFixtures.grid(trained: [], selected: nil)
            }
        }

        @Test func monthGridStartingOnMonday() throws {
            // The same month in a Monday-first week: every cell moves one column left. The image
            // that shows the headings and the days moving together rather than only one of them.
            try assertSnapshots(named: "Calendar-grid-monday") {
                CalendarFixtures.grid(calendar: CalendarFixtures.mondayFirst)
            }
        }

        @Test func dayCells() throws {
            // G-4.5's three states side by side, which is the picture the rule is actually about:
            // untrained, trained (a fill and a dot), and trained-and-open (a ring on top). No pair
            // of them differs by tint alone.
            try assertSnapshots(named: "Calendar-day-cells") {
                HStack(spacing: Spacing.md.points) {
                    CalendarFixtures.cell(day: 12, hasTraining: false, isSelected: false)
                    CalendarFixtures.cell(day: 13, hasTraining: true, isSelected: false)
                    CalendarFixtures.cell(day: 14, hasTraining: true, isSelected: true)
                }
                .environment(\.locale, CalendarFixtures.locale)
            }
        }

        @Test func dayCard() throws {
            // A session's row inside the day section: the same card the list draws, less its date,
            // which the section's heading carries instead. The picture that shows the two not
            // printing the same day twice.
            try assertSnapshots(named: "Calendar-day-card") {
                SessionSummaryCard(summary: CalendarFixtures.session, unit: .kilograms, showsDate: false)
                    .environment(\.locale, CalendarFixtures.locale)
            }
        }

        @Test func monthHeader() throws {
            try assertSnapshots(named: "Calendar-header") {
                MonthHeader(
                    month: CalendarFixtures.january,
                    calendar: CalendarFixtures.calendar,
                    canShowEarlier: true,
                    canShowLater: false,
                    step: { _ in }
                )
                .environment(\.locale, CalendarFixtures.locale)
            }
        }

        @Test func nothingLoggedYet() throws {
            try assertSnapshots(named: "Calendar-empty") {
                EmptyStateView(
                    symbolName: "calendar",
                    headline: Text(HistoryStrings.calendarEmptyHeadline),
                    message: Text(HistoryStrings.calendarEmptyMessage),
                    action: StateAction(Text(HistoryStrings.calendarEmptyAction)) {}
                )
            }
        }

        @Test func readFailed() throws {
            try assertSnapshots(named: "Calendar-error") {
                ErrorStateView(
                    headline: Text(HistoryStrings.calendarErrorHeadline),
                    message: Text(HistoryStrings.calendarErrorMessage),
                    retry: {}
                )
            }
        }

        @Test func oneDayFailed() throws {
            // Under a grid that is still correct, so no headline — the picture the session list's
            // next-page failure has, for the same reason.
            try assertSnapshots(named: "Calendar-day-error") {
                ErrorStateView(message: Text(HistoryStrings.calendarDayError), retry: {})
            }
        }
    }

    /// What these references render.
    enum CalendarFixtures {
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

        /// The same calendar with the week starting on Monday.
        static var mondayFirst: Calendar {
            var calendar = self.calendar
            calendar.firstWeekday = 2
            return calendar
        }

        /// The month every reference here draws — January 2026, which starts on a Thursday.
        ///
        /// Resolved through the fixture's own calendar rather than written as an epoch offset: an
        /// instant is only a date once a time zone says so, and the constant would name a different
        /// month on a machine set west of UTC.
        static var january: Date { day(calendar, 1) ?? Date(timeIntervalSince1970: 0) }

        /// One session's row, as the day section draws it.
        static let session = SessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001") ?? UUID(),
            date: january,
            exerciseNames: ["Back Squat", "Bench Press"],
            setCount: 8,
            tonnage: Weight(grams: 7_240_000),
            notes: ""
        )

        /// The grid, with `trained` marked and `selected` open.
        ///
        /// - Parameters:
        ///   - calendar: Which calendar to lay the month out in.
        ///   - trained: Which days of the month carry training.
        ///   - selected: Which day is open, if any.
        /// - Returns: The grid.
        static func grid(
            calendar: Calendar = CalendarFixtures.calendar,
            trained: [Int] = [1, 3, 6, 8, 13, 15, 20, 22, 27, 31],
            selected: Int? = 13
        ) -> some View {
            MonthGridView(
                grid: MonthGrid(containing: day(calendar, 1) ?? january, in: calendar),
                trainingDays: Set(trained.compactMap { day(calendar, $0) }),
                selectedDay: selected.flatMap { day(calendar, $0) },
                calendar: calendar,
                select: { _ in }
            )
            .environment(\.locale, locale)
        }

        /// One cell, on its own.
        ///
        /// - Parameters:
        ///   - day: Which day of January it draws.
        ///   - hasTraining: Whether it is marked.
        ///   - isSelected: Whether it is open.
        /// - Returns: The cell.
        static func cell(day number: Int, hasTraining: Bool, isSelected: Bool) -> some View {
            CalendarDayCell(
                day: day(calendar, number) ?? january,
                calendar: calendar,
                hasTraining: hasTraining,
                isSelected: isSelected,
                select: {}
            )
        }

        /// A day of January 2026, as its first instant.
        ///
        /// - Parameters:
        ///   - calendar: The calendar to resolve it in.
        ///   - number: The day of the month.
        /// - Returns: The instant, or `nil` if the calendar could not answer.
        private static func day(_ calendar: Calendar, _ number: Int) -> Date? {
            calendar.date(from: DateComponents(year: 2026, month: 1, day: number))
        }
    }

#endif
