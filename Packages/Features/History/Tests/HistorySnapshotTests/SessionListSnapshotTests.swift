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
            SessionSummaryCard(
                summary: summary, unit: unit, finish: finishes ? {} : nil
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            // The date goes through `Text(_:format:)`, which resolves its time zone from the
            // environment — so an unpinned reference is only reproducible while the fixture's
            // instant happens to fall on one day in every zone. This one does; pinning is what
            // stops the next fixture from depending on that.
            .environment(\.timeZone, .gmt)
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
        private static let day = Date(timeIntervalSince1970: 1_700_000_000)

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
