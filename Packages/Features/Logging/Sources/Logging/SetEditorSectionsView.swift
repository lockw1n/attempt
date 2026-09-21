import DesignSystem
import Localization
import PowerliftingCore
import SwiftUI

/// A checklist row's Log sheet: one section per planned group (`FR-18.6.2`, `FR-18.6.5`,
/// `FR-18.6.6`).
///
/// **A type of its own rather than a branch inside ``SetEditorFields``**, which is what keeps the
/// free workout's form provably untouched (`OUT-18.6`): that one collects one set and has no
/// sections to grow.
///
/// **With one section this draws exactly what the row's form drew before the sections existed** —
/// the head, the plate row, the Planned / Actual pair and the fold, in that order and at that
/// spacing. It is `FR-18.6.2`'s closing clause, and the `Log-sheet-*` references are the
/// measurement: if one of them moves, the section chrome leaked into the common case.
///
/// **The per-set fold's reset is attached per section.** The fold holds one entry per set,
/// prefilled from its own section's form, so a section whose reps or count move leaves entries
/// that section would ignore — and the section next to it must not be re-opened by it.
struct SetEditorRowFields: View {
    /// Every section, and what the lifter has entered in each.
    @Binding var sections: SetEditorSections

    /// Which form is drawn — always a row's here, and passed down for the heading and the fields
    /// the mode decides.
    let mode: SetEditorMode

    /// The modifier terms on offer (`FR-1.2.8`), handed down to the per-set rows.
    let vocabulary: SetModifierVocabulary

    /// The gym `FR-1.4.1`'s loading is worked out on.
    let equipment: PlateCalculatorStore

    /// The sections, stacked.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            ForEach(sections.sections.indices, id: \.self) { index in
                SetEditorHead(
                    draft: binding(at: index),
                    mode: mode,
                    equipment: equipment,
                    sectionTitle: sections.title(at: index),
                    isFirstSection: index == 0)
                // Below Reps rather than under the load it describes, and that is `FR-17.1.6`
                // deciding it — see ``SetEditorPlateRow``.
                SetEditorPlateRow(draft: binding(at: index), equipment: equipment)
                PlannedActualPair(
                    plan: sections.sections[index].plan, draft: sections.sections[index].draft)
                SetDetailsFold(draft: binding(at: index), vocabulary: vocabulary)
                    .onChange(of: sections.sections[index].draft.repsText) { reset(index) }
                    .onChange(of: sections.sections[index].draft.setsText) { reset(index) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One section's draft, writeable.
    ///
    /// - Parameter index: The section.
    /// - Returns: The binding the section's fields write through.
    private func binding(at index: Int) -> Binding<SetDraft> {
        Binding(
            get: { sections.sections[index].draft },
            set: { sections.replace($0, at: index) })
    }

    /// Re-opens a section's per-set entries over its current form, where it has any.
    ///
    /// A no-op while that fold is closed, which is what keeps this off every keystroke.
    ///
    /// - Parameter index: The section whose form moved.
    private func reset(_ index: Int) {
        sections.replace(sections.sections[index].draft.resettingDetails(), at: index)
    }
}
