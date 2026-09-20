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

    /// Whether the row keeps `FR-17.9.2`'s circle's width when it has no circle (`FR-18.3.1`).
    ///
    /// **The scheme's column is the day's, not the row's.** A circle is 60 pt of the row's trailing
    /// edge and only an unanswered row with a load carries one, so a column right-aligned inside
    /// each row's own text would step 60 pt sideways every time a row was answered — which is the
    /// opposite of *one edge down the screen*. The section answers this once for every row it
    /// draws, so a day whose rows all lack a circle — a past day (`FR-17.7.6`) — keeps the width.
    ///
    /// **Required, with no default** (`T-16.17`): a default here is a decision about the day taken
    /// by a row that cannot see it.
    let reservesCircle: Bool

    /// Which of the exercise's two names reads (`G-3.2`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    /// Whether the row can afford ``reservesCircle``'s 60 points.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whether this row draws `FR-17.9.2`'s circle at all — the row must have one to offer and a
    /// surface that takes the write (`FR-17.7.6`).
    private var drawsCircle: Bool { row.hasCircle && answer != nil }

    /// Whether this row actually keeps the circle's width.
    ///
    /// **The alignment is worth 60 points until it is not.** At an accessibility size a scheme is
    /// wider than the column whatever is done, so it wraps — and a wrapped scheme has no single
    /// right edge to line up with the row above it. The 60 points buy nothing there and cost a
    /// line break, so the row spends them on the numbers instead. At every other size the column
    /// is what `FR-18.3.1` asks for.
    private var keepsCircleWidth: Bool {
        reservesCircle && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md.points) {
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                Text(verbatim: row.exercise?.displayName(for: locale) ?? "")
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textPrimary)
                    // NFR-18.2: the name is what gives way, and giving way means WRAPPING. Without
                    // this a `Text` narrower than one of its own words truncates rather than
                    // breaking it — `Dumbbell Fly` came back as `Dum…` at accessibility3 while the
                    // four-word Ukrainian name beside it wrapped, because that one had somewhere
                    // to break. Nothing in this stack scales, so T-1.96's pairing trap does not
                    // apply: there is no flexible sibling to pay for this one.
                    .fixedSize(horizontal: false, vertical: true)
                lines
                setNotes
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the row says under the exercise's name — one line or two (`FR-17.9.3`, `FR-18.3.1`,
    /// `FR-18.3.2`).
    ///
    /// **Four states, and each says a different thing.** Unanswered says what is prescribed.
    /// Skipped says so and says nothing about loads, there being none. Logged exactly as planned
    /// collapses to one line, because *Planned 100 × 5 × 5 / Did 100 × 5 × 5* is the same sentence
    /// twice. Logged otherwise is the only case that owes two.
    ///
    /// **The scheme is a column and the words are a label beside it** (`F-07`). Each state's words
    /// used to carry the numbers inside a format string — *Planned %@*, *%@ · as planned* — and the
    /// numbers were the caption-sized end of it. They are now the trailing column every state
    /// shares, so a screenful of rows reads down one edge, which is the whole of `FR-18.3.1`. The
    /// word and its glyph stay on the leading edge, where `G-4.5` needs them: the state is never
    /// tint alone. *As planned* is still **one** row rather than a *Planned*/*Did* pair.
    @ViewBuilder private var lines: some View {
        switch row.answer {
        case .unanswered:
            PlanSchemeLines(schemes: schemes(row.plan))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .skipped:
            Label {
                Text(LoggingStrings.dayRowSkipped)
            } icon: {
                Image(systemName: "minus.circle")
            }
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
        case .logged where row.wasAsPlanned:
            schemeRow(row.performed) { done(Text(LoggingStrings.dayRowAsPlanned)) }
            recordMark
        case .logged:
            if !row.plan.isEmpty {
                schemeRow(row.plan) { planned(Text(LoggingStrings.dayRowPlanned)) }
            }
            schemeRow(row.performed) { done(Text(LoggingStrings.dayRowDid)) }
            recordMark
        }
    }

    /// One labelled line of the answer — the word on the leading edge, the groups on the trailing.
    ///
    /// - Parameters:
    ///   - targets: The groups that line draws.
    ///   - label: What names them.
    /// - Returns: The line.
    private func schemeRow<Label: View>(
        _ targets: [WeekPlanTarget], @ViewBuilder label: () -> Label
    ) -> some View {
        PlanSchemeRow(schemes: schemes(targets), label: label)
    }

    /// The groups of one side of the answer, one rendered line each.
    ///
    /// - Parameter targets: The groups to render.
    /// - Returns: `140 kg × 5 × 5` per group, in order.
    private func schemes(_ targets: [WeekPlanTarget]) -> [String] {
        WeekPlanTargets.lines(
            targets, unit: unit, precision: displayPrecision, locale: locale)
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
            Text(LoggingStrings.setNote(note))
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A secondary line.
    ///
    /// **At the scheme's size rather than the caption's** (`FR-18.3.2`): *Planned* names the column
    /// beside it, and a label two steps smaller than what it names is the hierarchy `F-07` was
    /// about. The colour still separates the two — the prescription is secondary, what was done is
    /// not.
    ///
    /// - Parameter text: What it says.
    /// - Returns: The line.
    private func planned(_ text: Text) -> some View {
        text
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A label that carries the answer.
    ///
    /// **Never by tint alone** (`G-4.5`): the glyph and the words carry it, and `G-7.3`'s green is
    /// added to them. The green stops at the label — the numbers beside it are the row's primary
    /// fact and take the primary colour (`FR-18.3.1`).
    ///
    /// - Parameter text: What it says.
    /// - Returns: The label.
    private func done(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(Typography.body.font)
        .foregroundStyle(ColorToken.positive)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The circle, where the row has one, and the menu that every row has.
    ///
    /// **The circle is a 60 pt target** (T-16.02, `G-4.3`) and it is a bare `Button` rather than one
    /// of `DesignSystem`'s action styles: those fill their width, and this one is a circle beside a
    /// two-line row.
    @ViewBuilder private var controls: some View {
        HStack(spacing: Spacing.xs.points) {
            if !drawsCircle, keepsCircleWidth {
                // The circle's width, kept so the schemes beside it stay in one column — see
                // ``reservesCircle``. Clear rather than a disabled control: there is nothing here
                // to press, and VoiceOver is told so.
                Color.clear
                    .frame(width: TouchTarget.logging.points, height: TouchTarget.logging.points)
                    .accessibilityHidden(true)
            }
            if drawsCircle, let answer {
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
}
