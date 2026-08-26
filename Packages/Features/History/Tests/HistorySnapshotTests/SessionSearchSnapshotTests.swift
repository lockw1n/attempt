#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import History

    // TR-1.12 for `FR-1.5.4`'s search, on the same terms as the session list's own references: the
    // pieces are rendered rather than the screen. That is not only the usual reason here — the search
    // field is `.searchable`, which the enclosing `NavigationStack` places and `ImageRenderer` would
    // draw as its unsupported-view placeholder. What is worth a picture is what search *adds*: the
    // "matched in" block on a result card, and the state a query that found nothing lands on.
    //
    // EVERY REFERENCE PINS ITS LOCALE AND TIME ZONE, for the reason the session list's file gives.

    @MainActor
    @Suite("History search snapshots")
    struct SessionSearchSnapshotTests {
        @Test func resultMatchedEverywhere() throws {
            // The tallest a result gets: a day that already clips two things, plus all three
            // "matched in" lines and a set note under them. If the block fits here it fits.
            try assertSnapshots(named: "SessionList-row-match") {
                Fixtures.card(
                    Fixtures.longDay,
                    match: SearchMatch(
                        fields: [.exerciseName, .sessionNote, .setNote],
                        setNote: "Third single felt slow off the floor — dropped the last one."
                    )
                )
            }
        }

        @Test func resultMatchedOnASetNoteAlone() throws {
            // The case the block exists for: nothing else on this card contains the query, so the
            // caption and the note beneath it are the whole of why the row is on screen.
            try assertSnapshots(named: "SessionList-row-match-setnote") {
                Fixtures.card(
                    Fixtures.squatDay,
                    match: SearchMatch(fields: .setNote, setNote: "Knee wrap on.")
                )
            }
        }

        @Test func nothingMatched() throws {
            // Deliberately a different picture from the list's own empty state: the history may be
            // full, and the action clears the field rather than starting a workout.
            try assertSnapshots(named: "SessionList-nomatches") {
                EmptyStateView(
                    symbolName: "magnifyingglass",
                    headline: Text(HistoryStrings.noMatchesHeadline),
                    message: Text(HistoryStrings.noMatchesMessage),
                    action: StateAction(Text(HistoryStrings.noMatchesAction)) {}
                )
            }
        }
    }

    extension Fixtures {
        /// One result row, rendered for the locale and zone every reference here is recorded in.
        ///
        /// - Parameters:
        ///   - summary: The row.
        ///   - match: Why a search put it on screen.
        ///   - unit: The unit its tonnage reads in (`G-3.1`).
        /// - Returns: The card.
        static func card(
            _ summary: SessionSummary, match: SearchMatch, unit: MassUnit = .kilograms
        ) -> some View {
            SessionSummaryCard(summary: summary, unit: unit, match: match)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
        }
    }

#endif
