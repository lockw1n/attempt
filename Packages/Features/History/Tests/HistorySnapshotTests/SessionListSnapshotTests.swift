#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import History

    // TR-1.12 for the session list, on the same terms as every other screen's references: the pieces
    // are rendered rather than the screen, because a screen builds its own state over a repository and
    // a reference must not need one. The copy is the real copy — a reference over placeholder text
    // would not catch the line that stops fitting at the largest Dynamic Type size.
    //
    // EVERY REFERENCE HERE PINS ITS LOCALE, and that is not decoration. `ImageRenderer` resolves
    // `@Environment(\.locale)` from whatever the machine is set to, and the harness does not pin one
    // — so a Mac whose region writes `7 240` records a reference a Mac whose region writes `7,240`
    // cannot match. This is the first snapshot suite here to render a grouped number, so it is the
    // first place it could bite; the same trap is waiting for any existing reference that grows one.
    //
    // THE LOADING STATE HAS NO REFERENCE HERE. It is `LoadingStateView`, whose `ProgressView` is
    // UIKit-backed, so `ImageRenderer` draws its unsupported-view placeholder — DesignSystem's own
    // suite already owns that picture, and a second copy of it would gate nothing.

    @MainActor
    @Suite("Session list snapshots")
    struct SessionListSnapshotTests {
        @Test func summaryRow() throws {
            try assertSnapshots(named: "SessionList-row") {
                Fixtures.card(Fixtures.squatDay)
            }
        }

        @Test func summaryRowWithNote() throws {
            // The two things a row can grow by: a session note (`FR-1.2.9`) and a long list of
            // exercises. Both are clipped, and this is the reference that shows where.
            try assertSnapshots(named: "SessionList-row-note") {
                Fixtures.card(Fixtures.longDay)
            }
        }

        @Test func summaryRowWithNothingLogged() throws {
            // A session started and finished empty. Not the empty *state* — the row is real, and
            // this is the picture that shows the two zeros reading as facts rather than as a fault.
            try assertSnapshots(named: "SessionList-row-empty-session") {
                Fixtures.card(Fixtures.emptyDay)
            }
        }

        @Test func summaryRowInProgress() throws {
            // `FR-16.4.3`. A workout being logged has a running total, and a running total drawn as
            // a finished one is the reading a row like this invites — so the state word stands
            // where the two numbers do, one step back in the ramp because it is not a measurement.
            try assertSnapshots(named: "SessionList-row-in-progress") {
                Fixtures.card(Fixtures.inProgressDay)
            }
        }

        @Test func summaryRowPlanned() throws {
            // The same rule at the other end: a workout dated ahead of today carries the zeros the
            // empty-session row above carries, and they mean the opposite thing. This is the
            // reference that settles that the two rows cannot be confused.
            try assertSnapshots(named: "SessionList-row-planned") {
                Fixtures.card(Fixtures.plannedDay)
            }
        }

        @Test func summaryRowOfferingFinish() throws {
            // `FR-16.4.4`'s way out of a workout left open past its own day. Secondary rather than
            // filled (`FR-16.6.4`): a history row is something to read, and twenty accents down a
            // list is a list with none. At `accessibility3` it is also where the command has to
            // survive under a state word that has taken the width.
            try assertSnapshots(named: "SessionList-row-finish") {
                Fixtures.card(Fixtures.staleDay, finishes: true)
            }
        }

        @Test func summaryRowFromAProgram() throws {
            // `FR-16.8.3`'s week and day, read off the session's own columns. Its own reference
            // because it is the line that retires the structure a note used to carry
            // (`DOD-16.1`) — the row above this one in the same suite is the note it replaces, and
            // the two have to be legible as different claims about the same workout.
            try assertSnapshots(named: "SessionList-row-program") {
                Fixtures.card(Fixtures.programDay)
            }
        }

        @Test func summaryRowInPounds() throws {
            // The unit is the settings row's (`G-3.1`), and it changes the numeral's width — which
            // is the half of it a unit test cannot see.
            try assertSnapshots(named: "SessionList-row-pounds") {
                Fixtures.card(Fixtures.squatDay, unit: .pounds)
            }
        }

        // MARK: - FR-16.6.3: the list itself, under its month headings

        @Test func monthSections() throws {
            // The list as a lifter reads it: two months, a heading each, and the rows inside one
            // card per month rather than one card per row. That is where the height comes from —
            // a card's inset is paid once per heading here and was paid once per row before.
            try assertSnapshots(named: "SessionList-months") {
                Fixtures.list(Fixtures.twoMonths)
            }
        }

        @Test func sixSessionsFitTheFirstScreen() throws {
            // FR-16.6.3's own number, asserted on the rendering's height rather than by eye —
            // T-16.03's above-the-fold budget, one screen over.
            //
            // THE BUDGET. The smallest device this app supports is the one with the smallest screen
            // still running its deployment target: 375 × 667 pt. This screen is a tab root inside
            // `RootTabView`'s `TabView`, so it loses the status bar (20 pt), a navigation bar
            // (44 pt) and the tab bar (49 pt) — that device having a home button rather than a home
            // indicator, so the tab bar is its full 49 and there is no inset under it.
            //
            // THE NAVIGATION BAR IS THE COLLAPSED ONE, AND THAT IS THE CLAIM. A tab root takes a
            // large title, and this screen carries `.searchable` under it: at rest the chrome is
            // some 150 pt rather than 44, and no list of six real rows fits under that on a 667 pt
            // screen. Both collapse on the first scroll and neither comes back until the list is
            // scrolled to its top, so "six sessions per screen" is a claim about the screen a lifter
            // browses their log on, which is the scrolled one.
            //
            // WHAT IS SUBTRACTED FROM THE MEASUREMENT. `Snapshot.render` pads every subject by
            // `Spacing.lg` on all four sides; the screen's own padding is the same measure, so the
            // vertical 32 pt is counted once rather than twice. The horizontal 32 pt is left where
            // it is and is why this stays conservative: the content renders 32 pt narrower than the
            // device would, so more lines wrap here than there.
            let budget = 667.0 - 20.0 - 44.0 - 49.0
            let rendered = try Snapshot.render(
                Fixtures.list(Fixtures.twoMonths), appearance: .light, typeSize: .default)
            let points = Double(rendered.height) / Snapshot.scale - 2 * Spacing.lg.points
            print("FR-16.6.3 six-session height: \(points) pt against a \(budget) pt budget")
            #expect(Fixtures.twoMonths.reduce(0) { $0 + $1.summaries.count } == 6)
            #expect(Fixtures.twoMonths.count == 2)
            #expect(points < budget)
        }

        @Test func nothingLoggedYet() throws {
            try assertSnapshots(named: "SessionList-empty") {
                EmptyStateView(
                    symbolName: "figure.strengthtraining.traditional",
                    headline: Text(HistoryStrings.emptyHeadline),
                    message: Text(HistoryStrings.emptyMessage),
                    action: StateAction(Text(HistoryStrings.emptyAction)) {}
                )
            }
        }

        @Test func readFailed() throws {
            try assertSnapshots(named: "SessionList-error") {
                ErrorStateView(
                    headline: Text(HistoryStrings.errorHeadline),
                    message: Text(HistoryStrings.errorMessage),
                    retry: {}
                )
            }
        }

        @Test func nextPageFailed() throws {
            // Deliberately a different picture from the one above: this one sits *under* rows that
            // loaded, so it carries no headline and its message names the half that failed.
            try assertSnapshots(named: "SessionList-more-error") {
                ErrorStateView(message: Text(HistoryStrings.moreErrorMessage), retry: {})
            }
        }
    }

    /// The rows these references render.
    enum Fixtures {
        /// One row, rendered for the locale every reference here is recorded in.
        ///
        /// - Parameters:
        ///   - summary: The row.
        ///   - unit: The unit its tonnage reads in (`G-3.1`).
        /// - Returns: The card.
        static func card(
            _ summary: SessionSummary, unit: MassUnit = .kilograms, finishes: Bool = false
        ) -> some View {
            // `.dayOfMonth`, because these are the LIST's rows: each pictures one thing a row can
            // say, and in the list a row sits under a heading that has named the month and the year
            // (`FR-16.6.3`). A surface rather than a heading around it, so each reference is one
            // row's content and nothing else — the list's own shape is `SessionList-months`.
            SessionSummaryCard(
                summary: summary, unit: unit, date: .dayOfMonth, finish: finishes ? {} : nil
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            // The date goes through `Text(_:format:)`, which resolves its time zone from the
            // environment — so an unpinned reference is only reproducible while the fixture's
            // instant happens to fall on one day in every zone. This one does; pinning is what
            // stops the next fixture from depending on that.
            .environment(\.timeZone, .gmt)
        }

        /// The list itself, rendered for the locale and calendar every reference here is recorded
        /// in.
        ///
        /// **The calendar is pinned as well as the zone**, and it has to be: the month a row falls
        /// under is cut in it, and a reference recorded a month either side of a boundary is a
        /// reference nothing else can reproduce.
        ///
        /// - Parameters:
        ///   - months: The sections to draw.
        ///   - unit: The unit the tonnages read in (`G-3.1`).
        /// - Returns: The list.
        static func list(_ months: [SessionMonthSection], unit: MassUnit = .kilograms) -> some View {
            SessionMonthList(months: months, unit: unit)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
                .environment(\.calendar, gmt)
        }

        /// Six workouts across two months, cut into sections the way the screen cuts them.
        ///
        /// **Through `SessionMonths.sections` rather than hand-built**, so the picture and the
        /// budget both render what the screen would: a fixture that assembled its own sections could
        /// disagree with the grouping and neither assertion would notice.
        ///
        /// **Six, because `FR-16.6.3` says six**, and spread three-and-three so the heading is paid
        /// twice — a fixture that put all six under one heading would measure the cheaper layout.
        static let twoMonths: [SessionMonthSection] = SessionMonths.sections(
            [
                everyday(10, daysBefore: 0, ["Back Squat", "Bench Press"], sets: 8, kilos: 7_240),
                everyday(11, daysBefore: 3, ["Deadlift", "Barbell Row"], sets: 6, kilos: 6_120),
                everyday(12, daysBefore: 9, ["Overhead Press", "Chin-Up"], sets: 9, kilos: 3_480),
                everyday(13, daysBefore: 20, ["Back Squat", "Bench Press"], sets: 8, kilos: 7_010),
                everyday(14, daysBefore: 25, ["Deadlift"], sets: 5, kilos: 5_900),
                everyday(15, daysBefore: 30, ["Bench Press", "Chin-Up"], sets: 7, kilos: 2_950),
            ],
            calendar: gmt
        )

        /// The calendar the list references are cut and drawn in.
        static let gmt: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            return calendar
        }()

        /// One ordinary finished workout, `daysBefore` days back from ``day``.
        ///
        /// - Parameters:
        ///   - index: Which row — its identity.
        ///   - daysBefore: How many days before the fixed day it was trained.
        ///   - names: What was trained.
        ///   - sets: Working sets performed.
        ///   - kilos: The tonnage, in whole kilograms.
        /// - Returns: The row.
        static func everyday(
            _ index: Int, daysBefore: Int, _ names: [String], sets: Int, kilos: Int
        ) -> SessionSummary {
            SessionSummary(
                id: identifier(index),
                date: day.addingTimeInterval(-Double(daysBefore) * 86_400),
                exerciseNames: names,
                setCount: sets,
                tonnage: Weight(grams: kilos * 1_000),
                notes: ""
            )
        }

        /// A day that looks like most days: two exercises, a round number of sets, no note.
        static let squatDay = SessionSummary(
            id: Fixtures.identifier(0),
            date: day,
            exerciseNames: ["Back Squat", "Bench Press"],
            setCount: 8,
            tonnage: Weight(grams: 7_240_000),
            notes: ""
        )

        /// The tallest a row gets: five exercises and a note, both clipped.
        static let longDay = SessionSummary(
            id: Fixtures.identifier(1),
            date: day,
            exerciseNames: [
                "Competition Squat", "Competition Bench Press", "Conventional Deadlift",
                "Barbell Row", "Weighted Chin-Up",
            ],
            setCount: 23,
            tonnage: Weight(grams: 18_650_000),
            notes: "Long meet-week session — everything felt fast until the third deadlift single."
        )

        /// A day of a program: the same session as ``squatDay``, started from week 2 day 1.
        static let programDay = SessionSummary(
            id: Fixtures.identifier(3),
            date: day,
            exerciseNames: ["Back Squat", "Bench Press"],
            setCount: 8,
            tonnage: Weight(grams: 7_240_000),
            notes: "",
            programPosition: ProgramPosition(week: 2, day: 1)
        )

        /// A session that was started, then finished with nothing in it.
        static let emptyDay = SessionSummary(
            id: Fixtures.identifier(2),
            date: day,
            exerciseNames: [],
            setCount: 0,
            tonnage: .zero,
            notes: ""
        )

        /// A workout being logged right now: the row has a running total and says so instead
        /// (`FR-16.4.3`).
        static let inProgressDay = SessionSummary(
            id: Fixtures.identifier(3),
            date: day,
            exerciseNames: ["Back Squat"],
            setCount: 3,
            tonnage: Weight(grams: 1_500_000),
            notes: "",
            lifecycle: .inProgress
        )

        /// A workout dated ahead of today, its sets written and none of them attempted.
        ///
        /// **The numbers are the zeros a planned day really carries**, which is the point: the
        /// reference is what settles that the row says *Planned* rather than `0 sets, 0 kg`.
        static let plannedDay = SessionSummary(
            id: Fixtures.identifier(4),
            date: day,
            exerciseNames: ["Back Squat", "Bench Press"],
            setCount: 0,
            tonnage: .zero,
            notes: "",
            lifecycle: .planned
        )

        /// A workout left open past its own training day — the one row that offers a way out.
        static let staleDay = SessionSummary(
            id: Fixtures.identifier(5),
            date: day,
            exerciseNames: ["Deadlift"],
            setCount: 2,
            tonnage: Weight(grams: 1_000_000),
            notes: "",
            lifecycle: .inProgress,
            canFinish: true
        )

        /// The day every reference is dated, so no image depends on when it was rendered.
        static let day = Date(timeIntervalSince1970: 1_700_000_000)

        /// A stable identifier for a reference's row. Nothing draws it; a row needs one to exist.
        ///
        /// - Parameter index: Which row.
        /// - Returns: The identifier, or a fresh one if the spelling is ever broken — a reference
        ///   does not render an identifier, so there is nothing here worth trapping over.
        static func identifier(_ index: Int) -> UUID {
            UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index))") ?? UUID()
        }
    }

#endif
