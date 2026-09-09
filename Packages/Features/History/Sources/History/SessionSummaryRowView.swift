import AppNavigation
import DesignSystem
import Localization
import PowerliftingCore
import SwiftUI

// A file of its own rather than the foot of `SessionListView.swift`, which had reached SwiftLint's
// file ceiling: the list and the row grow for different reasons — a state being added to the screen,
// and a fact being added to one session's line.

/// One session on a card of its own — `FR-1.5.1`'s four facts, wherever a session is drawn outside
/// the chronological list.
///
/// **The card is a wrapper around ``SessionSummaryRow`` and nothing else**, because neither list
/// draws one: their rows sit inside a month's or a week's section (`FR-16.6.3`, `FR-17.11.1`),
/// which is the card. What still draws a session on its own is a search result.
///
/// Takes the summary and the unit rather than the state, so a reference can render it without a
/// repository behind it.
struct SessionSummaryCard: View {
    /// The row.
    let summary: SessionSummary

    /// The unit the tonnage is shown in (`G-3.1`).
    let unit: MassUnit

    /// How the row names its own day. See ``SessionSummaryRow/date``.
    ///
    /// No ``SessionSummaryRow/position`` here, deliberately: the card is drawn by a search result
    /// and by nothing else, and a result is one workout rather than a day of a week, so the only
    /// reading it ever needs is the row's own default. A pass-through nothing sets would be a
    /// default a later host inherits without choosing it.
    var date: SessionRowDate = .full

    /// Why a search put this row on screen, or `nil` (`FR-1.5.4`).
    var match: SearchMatch?

    /// Where tapping the row's own content leads, or `nil` where the caller wraps this card itself.
    var destination: Route?

    /// Ends the workout this row describes (`FR-16.4.4`), or `nil`.
    var finish: (() -> Void)?

    /// The row, on a surface.
    var body: some View {
        Card {
            SessionSummaryRow(
                summary: summary,
                unit: unit,
                date: date,
                match: match,
                destination: destination,
                finish: finish
            )
        }
    }
}

/// One session, as `FR-1.5.1`'s four facts: the day, what was trained, how many working sets, and
/// what they weighed.
///
/// **Two lines for an ordinary workout, and that is `FR-16.6.3`.** The day and the two numbers share
/// the top line — they are the row's identity and its measurement, and neither needs a line of its
/// own — with what was trained under them, clipped to one. A note, a program's week and day, and a
/// search's reason for the match each add one more line and only to the rows that carry them.
///
/// Takes the summary and the unit rather than the state, so a reference can render it without a
/// repository behind it.
struct SessionSummaryRow: View {
    /// The row.
    let summary: SessionSummary

    /// The unit the tonnage is shown in (`G-3.1`).
    let unit: MassUnit

    /// How much of its own day the row names.
    ///
    /// **Two answers, because the row is drawn under two kinds of heading** — one that names the
    /// period it falls in (`FR-16.6.3`'s month, `FR-17.11.1`'s week) and none at all (a search
    /// result). A row is not free to repeat what the heading above it just said, on screen or to
    /// VoiceOver, and it is not free to leave a reader unable to say when the workout was either.
    var date: SessionRowDate = .full

    /// Whether a session with no program stamp says so, or draws nothing (`FR-17.11.1`).
    ///
    /// **An enum beside ``date``, and for its reason**: the row is drawn under headings that make
    /// different claims. Under a month it is one workout among a log's, and a workout outside a
    /// program is the ordinary case there — a label on every second row would be noise. Under a
    /// *week* the same row is a day of a plan carried out, so a day outside one is a fact about the
    /// week rather than a missing label.
    var position: SessionRowPosition = .whenPresent

    /// Why a search put this row on screen, or `nil` where the row is not a result (`FR-1.5.4`).
    ///
    /// An option on the list's own row rather than a wrapper around it, because the explanation
    /// belongs *inside* the row: a caption floating beneath one reads as a caption on the next.
    var match: SearchMatch?

    /// Where tapping the row's own content leads, or `nil` where the caller wraps this row itself.
    var destination: Route?

    /// Ends the workout this row describes (`FR-16.4.4`), or `nil` where the row does not offer it.
    ///
    /// **An option, like ``match``, and for the same reason.** The row is drawn in three places —
    /// the list, a calendar day and a search result — and a command is worth offering only where a
    /// tap on it leads somewhere: the list is the surface a lifter browses their own log from.
    var finish: (() -> Void)?

    /// Which locale the day, the names and the numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The facts, and the command under them where there is one.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            if let destination {
                NavigationLink(value: destination) { facts }
                    .buttonStyle(.plain)
            } else {
                facts
            }
            finishCommand
        }
    }

    /// Everything the row says about the workout — what a tap on it opens.
    ///
    /// **`Spacing.xs` between the lines rather than `Spacing.md`** (`FR-16.6.3`): these are lines of
    /// one paragraph about one workout, not sections of a card, and at the old measure three of them
    /// spent more height on the gaps than on the text.
    private var facts: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            headline

            if let line = positionLine {
                // `FR-16.8.3` read off the session's own columns. Above the exercises because
                // it says which workout this was rather than what was in it — and this is the
                // row a lifter used to read "W2D1" off the note below (`DOD-16.1`).
                Text(line)
                    .font(Typography.metricContext.font)
                    .foregroundStyle(ColorToken.textSecondary)
            }

            exercises

            if !summary.notes.isEmpty {
                // `FR-1.2.9`'s session note, readable for the first time. Clipped to **one** line
                // (`FR-16.6.3`): this is a summary, and a paragraph typed at the rack would
                // otherwise be the tallest thing in the list.
                Text(verbatim: summary.notes)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .lineLimit(1)
            }

            if let match {
                matched(match)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The day and the two numbers, on one line where they fit (`FR-16.6.3`).
    ///
    /// **One line, and it is the whole of where the density comes from inside a row.** The date
    /// identifies the workout and the metrics measure it; neither is prose, so neither needs the
    /// width. `ViewThatFits` is what keeps that from being a claim about English at the default type
    /// size — at `accessibility3`, or in a locale that writes a longer date, the two stack exactly as
    /// they always did.
    ///
    /// Under a heading that already names the day the metrics stand alone: there is nothing to pair
    /// them with.
    @ViewBuilder private var headline: some View {
        if let style = date.style(locale: locale) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md.points) {
                    day(style)
                    Spacer(minLength: Spacing.sm.points)
                    metrics
                }
                VStack(alignment: .leading, spacing: Spacing.xs.points) {
                    day(style)
                    metrics
                }
            }
        } else {
            metrics
        }
    }

    /// The training day (`FR-1.2.1` backdates, so this is not when it was entered).
    ///
    /// - Parameter style: How much of the date to render.
    /// - Returns: The day.
    private func day(_ style: Date.FormatStyle) -> some View {
        Text(summary.date, format: style)
            .font(Typography.cardTitle.font)
            .foregroundStyle(ColorToken.textPrimary)
    }

    /// Where the query was found, as one line per field in a fixed order.
    ///
    /// **Lines rather than one run-together sentence**: three short labels wrap where a joined
    /// sentence would break mid-phrase at the largest Dynamic Type size, and each is its own
    /// VoiceOver stop. The set-note match carries the note itself, being the only one of the three
    /// the row shows no other evidence of.
    ///
    /// **The block is `fixedSize`d vertically**, and the reference images are why: nested one level
    /// deeper than the row's other lines, it was offered the height left over rather than the height
    /// it wanted, and every line in it truncated to one — including the note, whose own two-line
    /// limit never got to apply. A caption reading *Matched a set no…* explains nothing, which is
    /// the whole of what this block is for.
    ///
    /// - Parameter match: Which fields matched, and the note behind a set-note match.
    /// - Returns: The caption block.
    @ViewBuilder private func matched(_ match: SearchMatch) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            if match.fields.contains(.exerciseName) {
                matchLabel(HistoryStrings.matchExercise)
            }
            if match.fields.contains(.sessionNote) {
                matchLabel(HistoryStrings.matchSessionNote)
            }
            if match.fields.contains(.setNote) {
                matchLabel(HistoryStrings.matchSetNote)
                if let note = match.setNote {
                    Text(verbatim: note)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One "matched in" line.
    private func matchLabel(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What was trained, run together as one phrase in the locale's own list style.
    ///
    /// **One line** (`FR-16.6.3`). A workout with five exercises in it is a workout whose row says
    /// the first few and stops; the whole list is one tap away, and the two lines this used to take
    /// were two lines on every row in the log.
    @ViewBuilder private var exercises: some View {
        if summary.exerciseNames.isEmpty {
            Text(HistoryStrings.noExercises)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textTertiary)
        } else {
            Text(verbatim: AppFormat.list(summary.exerciseNames, locale: locale))
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textSecondary)
                .lineLimit(1)
        }
    }

    /// `FR-16.4.4`'s way out of a workout left open past its own day.
    ///
    /// **Secondary**, on `FR-16.6.4`'s one-accent rule: a history row is something to read, and a
    /// filled button on each of twenty of them would be a screen with twenty accents.
    @ViewBuilder private var finishCommand: some View {
        if let finish {
            Button(action: finish) {
                Text(HistoryStrings.sessionFinish)
            }
            .buttonStyle(.secondaryAction(.fill))
        }
    }

    /// The two numbers, as one line — or, while the workout is open, what state it is in
    /// (`FR-16.4.3`).
    ///
    /// **Not `G-7.5`'s metric tiles, and the reference images are why.** Two tiles side by side in a
    /// list row wrap their numeral across three lines at the largest Dynamic Type size — a tonnage
    /// broken over three lines reads as three numbers — and they read out to VoiceOver as a label
    /// and a bare numeral each. The pattern is the dashboard's, where a number is the content; here
    /// it is a footnote on a row whose content is the day. One sentence is also one VoiceOver stop
    /// (`G-4.2`), so no accessibility override is needed to make it read properly.
    @ViewBuilder private var metrics: some View {
        if let state = HistoryStrings.sessionState(summary.lifecycle) {
            // A running total drawn as a finished one is the reading a row like this invites, and
            // over a session dated next week `0 sets, 0 kg` describes a workout that was missed
            // rather than one that has not happened yet. So the state word takes the line the two
            // numbers hold on a finished row.
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                Text(state)
                    .font(Typography.numericValue.font)
                    .foregroundStyle(ColorToken.textSecondary)

                if summary.setCount > 0 {
                    // **And the running total stays**, one step further back, under the word rather
                    // than instead of it: what has been logged so far is a fact about the day, and
                    // dropping it would answer `FR-16.4.3` by telling the lifter less than the row
                    // knows. A workout with nothing in it says only the word — there is no total.
                    Text(metricsSummary)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                }
            }
            // Two lines, one claim about the workout — and so one VoiceOver stop (`G-4.2`), as the
            // finished row's single sentence already is.
            .accessibilityElement(children: .combine)
        } else {
            // **A footnote, and the doc comment above is what says so**: on a browse row the day is
            // the content and the numbers are the annotation. Drawn at `numericValue` in
            // `textPrimary` they were the loudest thing in the list and they were also 200 pt wide,
            // which is what stopped them ever sharing the day's line (`FR-16.6.3`). The measurement
            // is unchanged, the sentence is unchanged, and so is what VoiceOver reads.
            Text(metricsSummary)
                .font(Typography.metricContext.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
    }

    /// What the row says about its place in a program, or `nil` where it says nothing.
    private var positionLine: LocalizedStringResource? {
        if let stamp = summary.programPosition {
            return HistoryStrings.programWeekAndDay(week: stamp.week, day: stamp.day)
        }
        return position == .always ? HistoryStrings.weekFreeWorkout : nil
    }

    /// The finished row's two numbers.
    private var metricsSummary: LocalizedStringResource {
        HistoryStrings.metricsSummary(sets: summary.setCount, volume: renderedTonnage)
    }

    /// The tonnage, to the whole unit — the dashboard's week tile renders the same figure through
    /// the same rule (`FR-16.5.2`).
    private var renderedTonnage: String {
        summary.tonnage.formatted(AppFormat.tonnage(in: unit, locale: locale))
    }
}

/// How much of its own day a session row names — which is decided by whatever heading it sits under
/// (`FR-16.6.3`, `FR-17.11.1`).
///
/// An enum rather than a `Bool`: "under a month heading" and "under no heading at all" are both rows
/// that must name the day, and they must name different amounts of it.
///
/// **The optional return is not a third case waiting to happen.** A `.hidden` case existed while the
/// calendar drew a day's sessions under a heading that named the day itself; `FR-17.11.2` retired
/// that section, and every heading over a row now names a *period* rather than a day. The signature
/// keeps room for one because a screen that names the day again would need it back.
enum SessionRowDate: Equatable {
    /// The whole date, for a row standing on its own — a search result.
    case full

    /// The weekday and the day of the month, for a row under a heading that names a period the day
    /// falls in: a month's section, or a week's.
    case dayOfMonth

    /// The style to render the day in, or `nil` where the row draws none.
    ///
    /// - Parameter locale: The locale to render for (`G-3.4`).
    /// - Returns: The style, or `nil`.
    func style(locale: Locale) -> Date.FormatStyle? {
        switch self {
        case .full: AppFormat.date(locale: locale)
        case .dayOfMonth: AppFormat.weekdayAndDay(locale: locale)
        }
    }
}

/// Whether a row names its place in a program even when it has none (`FR-17.11.1`).
///
/// An enum rather than a `Bool`, on ``SessionRowDate``'s rule: what a row owes depends on the
/// heading above it, and naming the two readings is what keeps a call site from reading as a flag
/// whose `true` means nothing in particular.
enum SessionRowPosition: Equatable {
    /// The position where the session carries one, and nothing where it does not — the log's rows,
    /// where a workout outside a program is the ordinary case.
    case whenPresent

    /// The position, or **Free workout** in its place — a week's rows, where every day is read as
    /// part of a plan carried out.
    case always
}
