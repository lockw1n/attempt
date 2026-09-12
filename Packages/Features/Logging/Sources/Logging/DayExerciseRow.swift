import DesignSystem
import DesignTokens
import Localization
import PowerliftingCore
import SwiftUI

/// One exercise on a day's checklist (`FR-17.9.1`, `FR-17.9.2`, `FR-17.9.3`).
///
/// **It replaces `SessionExerciseCardView` on a day.** That card is a workout being logged set by
/// set — a set list, a plan strip, a previous-performance strip, a pending-set question; this is a
/// line in a checklist, and the whole of what a lifter does to it is tap a circle.
///
/// **A per-set annotation has one home here and it is the *Did* line** (T-16.13's trap). This row
/// has no member rows to draw one on and nothing collapses, so a fact about the sets either appears
/// on that line or does not appear.
///
/// **Read-only is two closures being absent rather than a mode** (`FR-17.7.6`). A past day is this
/// row without `FR-17.9.2`'s circle and without `FR-17.9.6`'s skip — **Log** stays, because
/// `FR-17.7.5` is the one write a finished day still takes. A flag would have been a third thing to
/// keep in step with the two commands it governs.
struct DayExerciseRow: View {
    /// What this row draws.
    let row: DayRow

    /// The unit its loads read in (`G-3.1`).
    let unit: MassUnit

    /// Logs it exactly as planned, in one tap (`FR-17.9.2`), or `nil` where the surface offers no
    /// such write — a past day (`FR-17.7.6`).
    var answer: (() -> Void)?

    /// Opens the editor over it (`FR-17.9.3`). Never absent: it is the way an answer is corrected
    /// on a day that is over as much as it is the way one is given on a day that is not
    /// (`FR-17.7.5`).
    let log: () -> Void

    /// Records that the lifter is not doing it today (`FR-17.9.6`), or `nil` — see ``answer``.
    var skip: (() -> Void)?

    /// Which of the exercise's two names reads (`G-3.2`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md.points) {
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                Text(verbatim: row.exercise?.displayName(for: locale) ?? "")
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textPrimary)
                lines
                setNotes
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the row says under the exercise's name — one line or two (`FR-17.9.3`).
    ///
    /// **Four states, and each says a different thing.** Unanswered says what is prescribed.
    /// Skipped says so and says nothing about loads, there being none. Logged exactly as planned
    /// collapses to one line, because *Planned 100 × 5 × 5 / Did 100 × 5 × 5* is the same sentence
    /// twice. Logged otherwise is the only case that owes two.
    @ViewBuilder private var lines: some View {
        switch row.answer {
        case .unanswered:
            caption(Text(WeekPlanTargets.rendered(row.plan, unit: unit, precision: displayPrecision, locale: locale)))
        case .skipped:
            Label {
                Text(LoggingStrings.dayRowSkipped)
            } icon: {
                Image(systemName: "minus.circle")
            }
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
        case .logged where row.wasAsPlanned:
            done(Text(LoggingStrings.dayRowAsPlanned(performed: rendered(row.performed))))
            recordMark
        case .logged:
            if !row.plan.isEmpty {
                caption(Text(LoggingStrings.dayRowPlanned(plan: rendered(row.plan))))
            }
            done(Text(LoggingStrings.dayRowDid(performed: rendered(row.performed))))
            recordMark
        }
    }

    /// `FR-1.6.3`'s badge, where this row's work holds a record.
    ///
    /// **On the *Did* line's own row and nowhere else**, which is T-16.13's rule applied to a
    /// checklist: a per-set annotation owes three answers — the collapsed line, the member row, and
    /// which stays silent — and a `DayExerciseRow` has no member rows, so this is the only place it
    /// can be drawn and the question does not arise twice.
    @ViewBuilder private var recordMark: some View {
        if let badge = RecordBadge(marks: row.records) {
            RecordBadgeView(badge: badge)
        }
    }

    /// `FR-17.7.4`'s per-set notes, under the *Did* line.
    ///
    /// **The only place a day's row can draw one**, which is this view's own rule: there are no
    /// member rows here and nothing collapses. Each distinct note once — see ``DayRow/notes``.
    @ViewBuilder private var setNotes: some View {
        ForEach(row.notes, id: \.self) { note in
            caption(Text(LoggingStrings.setNote(note)))
        }
    }

    /// A secondary line.
    ///
    /// - Parameter text: What it says.
    /// - Returns: The line.
    private func caption(_ text: Text) -> some View {
        text
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A line that carries the answer.
    ///
    /// **Never by tint alone** (`G-4.5`): the glyph and the words carry it, and `G-7.3`'s green is
    /// added to them.
    ///
    /// - Parameter text: What it says.
    /// - Returns: The line.
    private func done(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(Typography.caption.font)
        .foregroundStyle(ColorToken.positive)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The circle, where the row has one, and the menu that every row has.
    ///
    /// **The circle is a 60 pt target** (T-16.02, `G-4.3`) and it is a bare `Button` rather than one
    /// of `DesignSystem`'s action styles: those fill their width, and this one is a circle beside a
    /// two-line row.
    @ViewBuilder private var controls: some View {
        HStack(spacing: Spacing.xs.points) {
            if row.hasCircle, let answer {
                Button(action: answer) {
                    Image(systemName: "circle")
                        .font(Typography.cardTitle.font)
                        .foregroundStyle(ColorToken.brandAccent)
                        .frame(
                            width: TouchTarget.logging.points,
                            height: TouchTarget.logging.points
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LoggingStrings.dayCircleAction))
            }
            Menu {
                Button(action: log) { Text(LoggingStrings.dayLogAction) }
                if row.answer == .unanswered, let skip {
                    Button(action: skip) { Text(LoggingStrings.daySkipAction) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    // G-4.3's logging target on both axes, not just the height: this menu is
                    // the only route to Log and Skip this exercise, so it is reached mid-set
                    // with the phone at arm's length — which is what the 60 pt figure is for.
                    .frame(width: TouchTarget.logging.points, height: TouchTarget.logging.points)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text(LoggingStrings.dayMenuAction))
        }
    }

    /// One side of the row's plan-or-performance line.
    ///
    /// - Parameter targets: The groups to render.
    /// - Returns: `140 kg × 5 × 5`, joined where there are several.
    private func rendered(_ targets: [WeekPlanTarget]) -> String {
        WeekPlanTargets.rendered(
            targets, unit: unit, precision: displayPrecision, locale: locale)
    }
}
