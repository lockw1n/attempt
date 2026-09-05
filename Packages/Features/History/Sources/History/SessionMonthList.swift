import AppNavigation
import DesignSystem
import Localization
import PowerliftingCore
import SwiftUI

/// The chronological log itself: `FR-16.6.3`'s month headings, and the rows under each.
///
/// **A view of its own rather than a `@ViewBuilder` on the screen**, on `SessionExerciseList`'s
/// rule: the screen builds its state over three repositories and a reference must not need one, so
/// what a reference renders has to be a type that takes values. It is also what keeps the six-rows
/// budget honest — the assertion measures this, and this is what the screen draws.
///
/// **A section per month rather than a card per row, and that is where the density comes from.** A
/// `Card` pays `Spacing.lg` of inset above and below whatever it holds, so twenty rows drawn as
/// twenty cards pay it twenty times; one card per heading pays it once for every row under that
/// heading. `FR-16.6.3`'s six-per-screen is not reachable by tightening a card — it is reachable by
/// having fewer of them.
struct SessionMonthList: View {
    /// The rows, already cut into months (`FR-16.6.3`).
    let months: [SessionMonthSection]

    /// The unit every tonnage here is shown in (`G-3.1`).
    let unit: MassUnit

    /// Called as a row appears, so the caller can page (`NFR-1.5`).
    ///
    /// **The list reports, and the caller decides.** Whether a given row is the last one in the log
    /// is the state's knowledge, not this view's: a month's last row is not the list's last row, and
    /// a section that thought otherwise would page on every month boundary.
    var appeared: (SessionSummary) -> Void = { _ in }

    /// Ends the workout a row describes (`FR-16.4.4`), where that row offers it.
    var finish: (SessionSummary) -> Void = { _ in }

    /// Which locale the headings, days, names and numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The calendar the headings are drawn in — the same one the sections were cut in.
    @Environment(\.calendar) private var calendar

    /// One section per month, newest first.
    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.lg.points) {
            ForEach(months) { month in
                GroupedSection(
                    Text(
                        month.start,
                        format: AppFormat.resolved(AppFormat.month(locale: locale), in: calendar))
                ) {
                    ForEach(month.summaries) { summary in
                        // The row carries its own link rather than sitting inside one, because a row
                        // that offers `FR-16.4.4`'s Finish has two controls in it — and a button
                        // nested in a link is a tap resolved by ancestry rather than by where the
                        // thumb landed.
                        SessionSummaryRow(
                            summary: summary,
                            unit: unit,
                            // The heading has just said the month and the year; the row owes the
                            // weekday and the day, and nothing else (`FR-16.6.3`).
                            date: .dayOfMonth,
                            destination: Route.history(.session(sessionID: summary.id)),
                            finish: summary.canFinish ? { finish(summary) } : nil
                        )
                        .onAppear { appeared(summary) }
                    }
                }
            }
        }
    }
}
