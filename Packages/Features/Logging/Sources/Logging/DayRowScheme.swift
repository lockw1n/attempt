import Foundation
import Localization
import PowerliftingCore

/// One labelled half of a day row's scheme table — what it is called, what it lists, how prominent
/// it is, and what it holds a record at (`FR-18.3.2`, `FR-18.3.6`, `FR-18.3.8`).
///
/// **The four facts travel as one value because a `body` cannot be asked about them.** `T-18.14`
/// measured that swapping two arguments in a `View`'s body survives the whole suite — an argument
/// list is readable by nothing — and `FR-18.3.6`'s whole content is *which half is secondary*. So
/// the emphasis arrives already attached to the half it belongs to, and ``DayExerciseRow`` draws
/// each section from this one value rather than choosing a label and a colour side by side.
struct DayRowSchemeSection: Equatable, Identifiable {
    /// Which half of the answer a section is.
    enum Role: Equatable, Sendable {
        /// What the routine prescribed, on an answered row that departed from it.
        case planned

        /// What was actually lifted, beside a ``planned`` section.
        case did

        /// What was lifted, where it was exactly what was planned — one section rather than two,
        /// because *Planned 100 × 5 × 5 / Did 100 × 5 × 5* is the same sentence twice.
        case asPlanned

        /// What names the lines.
        var label: LocalizedStringResource {
            switch self {
            case .planned: LoggingStrings.dayRowPlanned
            case .did: LoggingStrings.dayRowDid
            case .asPlanned: LoggingStrings.dayRowAsPlanned
            }
        }

        /// Whether the label carries the answer — `G-7.3`'s green and its checkmark (`G-4.5`).
        var carriesAnswer: Bool { self != .planned }
    }

    /// Which half this is.
    let role: Role

    /// The groups it lists, in order.
    let targets: [WeekPlanTarget]

    /// How prominent its lines are.
    let emphasis: PlanSchemeEmphasis

    /// The record each of its groups set, `nil` where it set none. Empty on a ``Role/planned``
    /// section: a prescription holds no records.
    let badges: [RecordBadge?]

    /// A row draws each role at most once, so the role identifies the section.
    var id: Role { role }
}

/// Which labelled halves a day's row draws, and how prominent each one is (`FR-18.3.6`).
///
/// **A plain type rather than a `switch` inside `DayExerciseRow.lines`**, which is
/// ``DayRowCircle``'s rule and ``SessionMenuContents``' — what a row draws in which state is the
/// claim worth a test, and written as branches inside a `body` no test can fail it.
enum DayRowScheme {
    /// What an **unanswered** row's plan takes, and the week's card with it (`FR-18.3.3`).
    ///
    /// **Primary, unchanged by this phase's second look at the row.** `FR-18.3.6` makes the planned
    /// numbers secondary only once there is a *Did* line to read them against; on a row nobody has
    /// answered the plan is still the fact read at the rack (`D-18.5`), and greying it there would
    /// be most of the way back to `F-07`.
    static let unansweredEmphasis: PlanSchemeEmphasis = .plan

    /// The labelled halves the row draws, in the order it draws them.
    ///
    /// **Empty for a row that is unanswered or skipped**, which is not the same as a row with
    /// nothing to say: an unanswered row draws its plan as a bare column with no label at all
    /// (``unansweredEmphasis``) and a skipped one draws a word and no numbers. Both are shapes
    /// rather than labelled halves, so neither is a section.
    ///
    /// - Parameter row: The row.
    /// - Returns: One section, two, or none.
    static func sections(for row: DayRow) -> [DayRowSchemeSection] {
        guard row.answer == .logged else { return [] }
        let badges = row.recordBadges
        if row.wasAsPlanned {
            return [
                DayRowSchemeSection(
                    role: .asPlanned, targets: row.performed, emphasis: .done, badges: badges)
            ]
        }
        let did = DayRowSchemeSection(
            role: .did, targets: row.performed, emphasis: .done, badges: badges)
        guard !row.plan.isEmpty else { return [did] }
        return [
            DayRowSchemeSection(
                role: .planned, targets: row.plan, emphasis: .reference, badges: []),
            did,
        ]
    }
}
