import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// What confirming the set editor writes — sets that do not exist yet, or a rewrite of one that
/// does (`FR-1.2.3`, `FR-1.2.7`, `FR-17.1.1`).
///
/// **The decision is a value rather than a branch buried in the screen**, and that is what makes it
/// answerable without one: which of these two a confirmed form resolves to is the single place
/// adding and editing part company, and a regression there appends a duplicate set where the user
/// asked for a correction.
///
/// **Adding carries rows rather than one set** (`NFR-17.3`). The form collects a *group*, so one
/// confirmation can be N sets; writing them one call at a time is what that requirement forbids.
enum SetEditorWrite: Equatable {
    /// Sets logged for the first time, against the exercise they belong to.
    case add(entryID: UUID, rows: [SetEntryValues])

    /// A set that already exists, rewritten where it sits.
    case rewrite(setID: UUID, entryID: UUID, values: SetEntryValues)
}

/// `FR-17.1`'s Log sheet — one form that answers *what did you do* for a whole exercise — and
/// `FR-1.2.3`'s add-set form and `FR-1.2.7`'s editor, which are the same sheet in its other mode.
///
/// **One form, and ``SetEditorMode`` is the difference.** A day's checklist row draws a Planned /
/// Actual pair under the fields, a collapsed **Per-set details** row and two actions; a free
/// workout draws today's six fields under a pinned plan line (`OUT-17.8`). Adding and editing
/// collect the same fields either way, so a second sheet would be the same layout maintained twice.
///
/// **Presented rather than drawn inside the row, and that is `NFR-1.4` deciding it.** Every logging
/// control has to sit in the lower two-thirds of the screen, reachable by one thumb; a draft row
/// inside the list would sit wherever the user had scrolled it to, and a sheet is the same place
/// for every exercise.
///
/// **The detents are the host's, and the two hosts differ.** A free workout offers medium and
/// large — medium is the lower half of the screen by construction, and large is there because at
/// `accessibility3` the fields no longer fit the medium one. A checklist row opens `.large` only,
/// and that is measured rather than chosen: see ``smallestScreen``.
///
/// **Three taps, counted rather than assumed** (`NFR-1.3`, `FR-17.1.7`): **Log** opens this already
/// filled in from the plan, one **+** moves the field being adjusted, **Save as done** stores it.
///
/// Taking a draft and closures rather than the store, so the form is picturable without one.
struct SetEditorSheet: View {
    /// What the user has entered so far.
    @State private var draft: SetDraft

    /// Whether the confirming command has been tapped over a draft that does not resolve.
    ///
    /// **What gates the refusal, and it is a *submission* rather than a keystroke** (`FR-17.1.6`).
    /// The form refuses only when asked to save: a lifter half-way through typing a weight has not
    /// made a mistake, and a duplicate whose stored rating is out of range arrives invalid through
    /// no keystroke of theirs — seeded the other way it opened complaining about a field nobody had
    /// touched.
    @State private var hasSubmitted = false

    /// Which form is drawn (`FR-17.1.1`).
    let mode: SetEditorMode

    /// What a routine prescribed for the set being logged or edited, or `nil` (`FR-15.3.1`).
    let prescribed: PlannedTargetGroup?

    /// The unit that prescription is shown in (`G-3.1`). Unused where there is none.
    let unit: MassUnit

    /// The modifier terms on offer (`FR-1.2.8`), handed down to the rows that pick from them.
    let vocabulary: SetModifierVocabulary

    /// The gym `FR-1.4.1`'s loading is worked out on, handed down to the row that shows it.
    let equipment: PlateCalculatorStore

    /// Logs the group, or saves the edit. The caller is what knows which row or set it is.
    let log: (SetDraft) -> Void

    /// Leaves without writing anything.
    let cancel: () -> Void

    /// Records that the lifter is not doing this exercise today (`FR-17.9.6`), or `nil` where the
    /// form is not over a checklist row.
    let skip: (() -> Void)?

    /// Soft-deletes the set being edited (`FR-1.2.7`). Never called while one is being added.
    let delete: () -> Void

    /// Builds the form over a draft.
    ///
    /// - Parameters:
    ///   - draft: What the form opens holding.
    ///   - mode: Which form is drawn (`FR-17.1.1`).
    ///   - prescribed: What a routine planned for it, where one did (`FR-15.3.1`).
    ///   - unit: The unit that prescription is shown in.
    ///   - vocabulary: The modifier terms on offer (`FR-1.2.8`).
    ///   - equipment: The gym `FR-1.4.1`'s loading is worked out on.
    ///   - log: Logs the group, or saves the edit.
    ///   - cancel: Closes the form.
    ///   - skip: Records that the exercise is not being done today. Row mode only.
    ///   - delete: Deletes the set being edited. Ignored while one is being added.
    init(
        draft: SetDraft,
        mode: SetEditorMode = .set(isEditing: false),
        prescribed: PlannedTargetGroup? = nil,
        unit: MassUnit,
        vocabulary: SetModifierVocabulary,
        equipment: PlateCalculatorStore,
        log: @escaping (SetDraft) -> Void,
        cancel: @escaping () -> Void,
        skip: (() -> Void)? = nil,
        delete: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: draft)
        self.mode = mode
        self.prescribed = prescribed
        self.unit = unit
        self.vocabulary = vocabulary
        self.equipment = equipment
        self.log = log
        self.cancel = cancel
        self.skip = skip
        self.delete = delete
    }

    /// The fields, scrolling, with the commands pinned beneath them.
    ///
    /// **The commands are outside the scroll view, and that is measured rather than assumed.** With
    /// them inside it, the confirming command sat below the fold at the medium detent —
    /// `NFR-1.3`'s third tap cost a scroll first, which is the one thing the three-tap count cannot
    /// afford. Pinned, the command is in the same place at either detent and at every Dynamic Type
    /// size, which is also what `NFR-1.4` asks for.
    var body: some View {
        VStack(spacing: Spacing.sm.points) {
            plannedTarget
            ScrollView {
                SetEditorFields(
                    draft: $draft,
                    mode: mode,
                    vocabulary: vocabulary,
                    equipment: equipment
                )
                .padding(Spacing.lg.points)
            }
            SetEditorCommands(
                showsRefusal: hasSubmitted && !draft.isLoggable,
                mode: mode,
                log: submit,
                cancel: cancel,
                skip: skip,
                delete: delete
            )
        }
        .background(ColorToken.background)
    }

    /// The height a checklist row's sheet has to open at, in points, on the smallest device the app
    /// supports (`FR-17.1.6`).
    ///
    /// **Measured, and it is why that sheet opens `.large` rather than at a detent.** The two
    /// regions the sheet stacks come to 554 pt at the default type size — a 352.5 pt head and
    /// 201.5 pt of pinned commands — against 667 pt of screen. Half of that screen does not hold
    /// them, and neither does any fraction worth offering: the nearest one that does is 0.84,
    /// which is `.large` wearing a number.
    ///
    /// `LogSheetSnapshotTests.weightAndRepsOpenAboveTheCommands` is that measurement, re-run on
    /// every snapshot pass, so a field added to ``SetEditorHead`` has to be argued against this
    /// rather than silently pushing Reps under the commands.
    static let smallestScreen = 667.0

    /// `FR-17.1.6`'s validation: the refusal appears at the first save over a draft that does not
    /// resolve, and the command refuses rather than being disabled.
    private func submit() {
        hasSubmitted = true
        guard draft.isLoggable else { return }
        log(draft)
    }

    /// `FR-15.3.1`'s target, where a routine planned this set — the free workout's reference line.
    ///
    /// **Above the scroll view rather than in the fields, and pinned for the commands' reason.**
    /// This sheet covers the card the target is drawn on, so without it the one moment the lifter
    /// is actually entering a number is the one moment the plan is not on screen. Inside the
    /// fields it would push the load and the repetitions below the fold at the medium detent,
    /// which is the measurement ``SetEditorFields`` is ordered around; pinned, it costs the form
    /// one line and moves nothing.
    ///
    /// **Never in a checklist row's form, which has its own reference and a better one.**
    /// ``PlannedActualPair`` draws what was prescribed against what the form says, it is derived
    /// from the row's whole plan rather than from the next unconsumed group, and it is therefore
    /// present in every state the sheet opens in. This line is not: it is read from
    /// ``SessionExercise/nextPlannedGroup``, which is `nil` before the day has a session — the
    /// first **Log** of every day — and `nil` again once the row's planned sets are all logged,
    /// which is every reopen of a fully answered row (`FR-17.7.5`). Drawn where it *is* available
    /// it would say what the pair says one line lower, and appear and vanish under a lifter who
    /// had changed nothing but the count (T-16.13's rule: when two places would say the same
    /// thing, one of them stays silent).
    @ViewBuilder private var plannedTarget: some View {
        if let prescribed, !mode.isRow {
            PlannedTargetLine(target: prescribed, comparison: nil, unit: unit)
                .padding(.horizontal, Spacing.lg.points)
                .padding(.top, Spacing.lg.points)
        }
    }
}
