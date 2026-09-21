import DesignSystem
import DesignTokens
import Foundation
import Localization
import PowerliftingCore
import SwiftUI

// The two views the day's checklist is drawn from, split out of `DayView.swift` at SwiftLint's
// file ceiling. Both are separate types rather than branches inside the screen, which is what
// makes a snapshot over one evidence about the screen (`T-16.17`) — so neither needed anything of
// `DayView`'s to move with it.

/// The day's rows, under the count of how many are answered (`FR-17.9.1`).
///
/// A view rather than a `GroupedSection` built inside the screen, which is `T-16.17`'s finding: the
/// heading, the grouping and what each row offers are the screen's decisions, and a fixture that
/// restates them pictures itself.
struct DayChecklistSection: View {
    /// The day's exercises, in order.
    let rows: [DayRow]

    /// How far through them the lifter is.
    let progress: DayProgress

    /// The unit their loads read in (`G-3.1`).
    let unit: MassUnit

    /// Logs one row exactly as planned (`FR-17.9.2`), or `nil` on a past day (`FR-17.7.6`).
    var answer: ((UUID) -> Void)?

    /// Opens the editor over one row (`FR-17.9.3`). Never absent — see ``DayExerciseRow/log``.
    let log: (UUID) -> Void

    /// Records that the lifter is not doing one row today (`FR-17.9.6`), or `nil` — see ``answer``.
    var skip: ((UUID) -> Void)?

    /// Takes one row's answer back (`FR-18.5.1`), or `nil` — see ``answer``.
    var reset: ((UUID) -> Void)?

    var body: some View {
        GroupedSection(
            Text(LoggingStrings.dayProgress(done: progress.answered, of: progress.total))
        ) {
            ForEach(rows) { row in
                DayExerciseRow(
                    row: row,
                    unit: unit,
                    // Rebound per row rather than passed through: the row's own commands take no
                    // argument, and an absent one here has to stay absent there.
                    answer: answer.map { command in { command(row.id) } },
                    log: { log(row.id) },
                    skip: skip.map { command in { command(row.id) } },
                    reset: reset.map { command in { command(row.id) } },
                    reservesCircle: reservesCircle)
            }
        }
    }

    /// Whether any row here carries `FR-17.9.2`'s circle, and therefore whether the ones that do
    /// not keep its width — see ``DayExerciseRow/reservesCircle``.
    private var reservesCircle: Bool {
        answer != nil && rows.contains { $0.hasCircle }
    }
}

/// The command that answers for everything that is left exactly as planned (`FR-17.9.9`).
///
/// **One command, since `FR-18.4.4`.** **Skip remaining** stood directly under it in the same
/// secondary text style, and the author skipped a whole day through its confirmation (`F-09`): the
/// command that answers *against* the plan was one slip from the one that answers *with* it. It is
/// in the day's overflow menu now, behind the `⋯` and among commands that are not the way a day is
/// normally answered.
///
/// **At the foot, under `+ Add exercise`, and secondary.** It is the exception rather than the way
/// a day is normally answered — the circle is — and a fill here would be a second primary action on
/// a screen whose accent belongs to the work.
struct DayFootCommands: View {
    /// Logs everything that is left exactly as planned.
    let logRemaining: () -> Void

    var body: some View {
        Button(action: logRemaining) {
            Text(LoggingStrings.dayLogRemainingAction)
        }
        .buttonStyle(.plain)
        .font(Typography.actionLabel.font)
        .foregroundStyle(ColorToken.textSecondary)
        .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points, alignment: .leading)
    }
}
