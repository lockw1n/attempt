import DerivedValues
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface

// A file of its own rather than the top of `SetEditorTarget.swift`: that one is what the sheet is
// presented *over*, this is what it holds while it is open.

/// One section of the Log sheet — a group's three fields and the plan they are measured against
/// (`FR-18.6.2`, `FR-18.6.5`).
///
/// **The plan travels with the draft rather than beside it.** A sheet with two sections has two
/// Planned / Actual pairs, and a parallel array of plans is one reorder away from drawing the
/// second group's target under the first group's numbers.
struct SetEditorSection: Equatable, Sendable {
    /// What the lifter has entered for this group.
    var draft: SetDraft

    /// The group the routine prescribed here, as a one-element list, or empty where it named none
    /// — a row the lifter added (`FR-1.2.2`), or a logged group beyond what the plan describes.
    let plan: [WeekPlanTarget]
}

/// What the Log sheet holds over a checklist row: one section per planned group, in the plan's
/// order (`FR-18.6.2`).
///
/// **`F-10` is what this type exists for.** The circle writes every planned group and the sheet
/// used to write one, so a plan of `57 × 10 × 3, 64 × 8 × 3` could only ever be logged exactly as
/// planned — a deviation in the second group was unrecordable, and once the row was answered the
/// circle was gone and nothing could record the whole exercise again.
///
/// **A section is matched to a logged group by *position*, never by what it holds.** Matching on
/// the load would pair a back-off set the lifter moved up with the top set it now weighs the same
/// as, and the rewrite that follows is positional (``SetGroupRewrite``) — so a form that had
/// paired them any other way would write the second group's numbers over the first group's rows.
///
/// **More logged groups than the plan names is the case nobody thinks of, and it is reachable.**
/// A row rewritten before this task collapsed every group into one form and could re-save it as
/// several; an imported session (`FR-16.4`) was never planned at all. Those extra groups get
/// sections of their own *after* the planned ones, prefilled from themselves — never dropped,
/// because a section the sheet does not draw is a group **Save as done** would delete.
///
/// **Warm-ups belong to the group that is open where they sit**, which for the warm-ups that
/// precede the first working set is the first section's fold. It is the only rule that keeps the
/// partition contiguous, and contiguity is what ``rows`` needs: the sections' rows concatenated
/// have to arrive in the order the stored sets are in, or the positional rewrite shifts every set
/// after the first warm-up. The second section's fold therefore offers no warm-up of its own
/// unless one was logged inside that group.
///
/// **A section takes its load from its *first* stored set, so a group led by a warm-up at a
/// lighter load rewrites its working sets to that load.** ``SetDraft/init(answering:unit:locale:)``
/// reads `logged.first`, the fold cannot express a per-set load at all (a different load is a
/// different group), and this sheet can only ever have written one load per group — so the state
/// is reachable from an import (`FR-16.4`) or a free workout's own form rather than from here.
/// It is older than the sections and they neither widen nor fix it: what they change is that the
/// flattening is now confined to the one group the warm-up sits in. Filed rather than carried,
/// because the fix is a per-set load and that is a form this phase does not have (`OUT-18.9`).
struct SetEditorSections: Equatable, Sendable {
    /// The sections, in the order they are drawn.
    private(set) var sections: [SetEditorSection]

    /// Builds the sections a checklist row's sheet opens with.
    ///
    /// - Parameters:
    ///   - row: The row's plan and everything already logged against it.
    ///   - unit: The unit the loads are entered in (`G-3.1`).
    ///   - locale: What the numbers are parsed and rendered in.
    init(answering row: SetEditorRow, unit: MassUnit, locale: Locale) {
        let planned = DayPerformance.collapsed(row.plan)
        let logged = Self.loggedGroups(row.logged)
        // At least one: a row the lifter added has neither a plan nor a set, and it still opens on
        // a form.
        let count = max(planned.count, logged.count, 1)
        sections = (0..<count).map { index in
            let plan = index < planned.count ? [planned[index]] : []
            var draft = SetDraft(
                answering: SetEditorRow(
                    plan: plan, logged: index < logged.count ? logged[index] : []),
                unit: unit,
                locale: locale)
            // `FR-18.6.4`, and only where there is more than one: a lone section at zero sets is
            // an answer that says nothing, which is what the count's floor of 1 has always
            // refused.
            if count > 1 { draft.minimumSets = 0 }
            return SetEditorSection(draft: draft, plan: plan)
        }
    }

    /// Wraps the free workout's single form, which has no sections and never grows one
    /// (`OUT-17.8`, `OUT-18.9`).
    ///
    /// - Parameter draft: The form.
    init(single draft: SetDraft) {
        sections = [SetEditorSection(draft: draft, plan: [])]
    }

    /// The one form, for the modes that have exactly one — see ``init(single:)``.
    var single: SetDraft { sections[0].draft }

    /// Replaces a section's draft.
    ///
    /// - Parameters:
    ///   - draft: What it now holds.
    ///   - index: Which section.
    mutating func replace(_ draft: SetDraft, at index: Int) {
        sections[index].draft = draft
    }

    /// The heading a section draws above its fields, or `nil` where it draws none.
    ///
    /// **A one-section sheet has no *Group 1*.** It is the commonest sheet in the app by far, the
    /// heading would name a distinction it does not have, and `FR-18.6.2` asks in so many words
    /// for that sheet to look exactly as it did.
    ///
    /// - Parameter index: The section.
    /// - Returns: The heading, or `nil`.
    func title(at index: Int) -> LocalizedStringResource? {
        sections.count > 1 ? LoggingStrings.setGroupHeading(index + 1) : nil
    }

    /// Every set **Save as done** writes, in the order they are stored in (`FR-18.6.3`).
    ///
    /// **One list rather than one per section**, because the write is one chained command
    /// (`NFR-18.3`): the rewrite matches these to the stored sets by position, and a section that
    /// writes nothing contributes nothing rather than a gap.
    var rows: [SetEntryValues] {
        sections.flatMap { $0.draft.resolvedGroup?.rows ?? [] }
    }

    /// Whether every section is at zero sets — the state **Save as done** is disabled in
    /// (`Q-18.7`).
    ///
    /// **Saving here would write a done entry holding no completed set, which is exactly what a
    /// skip is** (`FR-17.9.6`) — reached through a command that says the opposite. Unreachable on
    /// a one-section sheet, whose count floor is 1.
    var writesNothing: Bool {
        sections.allSatisfy { $0.draft.sets == 0 }
    }

    /// Whether the sheet resolves — what `FR-17.1.6`'s refusal is gated on.
    ///
    /// **A section at zero sets is exempt**, and it has to be: a group the lifter did not do is
    /// not a group they owe a load for, and a plan may name no load at all (`FR-15.2.2`).
    var isLoggable: Bool {
        !writesNothing && sections.allSatisfy { $0.draft.sets == 0 || $0.draft.isLoggable }
    }

    /// The logged sets partitioned into the groups the sheet draws a section for.
    ///
    /// `T-16.01`'s derivation over the working sets — ``DerivedValues/SetGrouping`` at
    /// ``DerivedValues/SetGrouping/Grain/loadAndReps`` — with the warm-ups placed back where they were logged,
    /// which is a placement rather than a second grouping. The result is a *contiguous* partition
    /// of `logged` in its own order: see the type's note for why that is load-bearing.
    ///
    /// - Parameter logged: Every set stored against the row, in order.
    /// - Returns: One list per group, or none where nothing is logged.
    static func loggedGroups(_ logged: [SetEntry]) -> [[SetEntry]] {
        guard !logged.isEmpty else { return [] }
        let runs = SetGrouping.groups(logged.filter { !$0.isWarmup }, at: .loadAndReps)
        guard runs.count > 1 else { return [logged] }
        var run: [UUID: Int] = [:]
        for (position, group) in runs.enumerated() {
            for set in group.sets { run[set.id] = position }
        }
        var groups = [[SetEntry]](repeating: [], count: runs.count)
        var current = 0
        for set in logged {
            if let position = run[set.id] { current = position }
            groups[current].append(set)
        }
        return groups
    }
}
