#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for FR-15.3's additions to the workout in progress, in a suite of its own because
    // `SessionSnapshotTests.swift` had reached `file_length`. The conventions are that file's — four
    // configurations per reference, the real copy, data through `AppFormat`.

    @MainActor
    @Suite("Planned-vs-actual snapshots")
    struct SessionPlanSnapshotTests {
        // MARK: - Planned vs actual (FR-15.3.1, FR-15.3.2)

        @Test func plannedCards() throws {
            // The target beside each logged set, the deviation mark where the set missed it, the
            // blank-weight target's third state — which is the one a "deviation of zero" would
            // silently swallow — and the **Planned next** section with its one-tap command.
            //
            // The whole reason this is a reference rather than an assertion: G-4.5 says a deviation
            // cannot be carried by colour alone, and whether the arrow and the sign are actually
            // drawn beside the magnitude is a claim only a picture settles. The accessibility3
            // configuration is the other half — the row was already spending its width on two 44pt
            // controls and the load before this line existed.
            try assertSnapshots(named: "Session-planned-cards") {
                fixedEnvironment { cards(PlanFixtures.deviations, expansion: [:]) }
            }
        }

        // MARK: - The check-off, in both of its words (FR-15.3.4)

        @Test func plannedCompletion() throws {
            // The same screen's other pair: an exercise finished early, pinned open so the checked
            // toggle is in the picture at all, and one skipped outright, left folded. Its own
            // reference rather than two more cards on the one above — see `PlanFixtures.deviations`
            // for why the four cannot share a rendering.
            try assertSnapshots(named: "Session-planned-done") {
                fixedEnvironment {
                    cards(PlanFixtures.completion, expansion: PlanFixtures.expansion)
                }
            }
        }

        // MARK: - Adjusting one of them (FR-15.3.5)

        @Test func setEditorAdjusting() throws {
            // FR-15.3.5's own surface: the set editor as the card opens it over a set that was
            // planned, which is where an actual result is corrected. Its own reference because the
            // target line is the one thing that distinguishes it from `Session-set-editor-edit`,
            // and because it is drawn *above* the fields rather than among them — a claim about
            // placement that only a picture makes.
            //
            // What it can check is the line and its placement, not the two numbers disagreeing:
            // every field here is a `TextField`, which rasterises as `ImageRenderer`'s
            // unsupported-view placeholder — the same limit `Session-set-editor-edit` renders
            // under. That the form opens holding the logged set rather than the plan is
            // `SetEditorWriteTests`' claim, and it is an assertion because a picture cannot make
            // it.
            try assertSnapshots(named: "Session-set-editor-adjust") {
                fixedEnvironment { adjustingEditor }
            }
        }

        /// One rendering of the card list, with everything it takes that this suite never varies.
        ///
        /// - Parameters:
        ///   - exercises: The cards to draw.
        ///   - expansion: Which of them are pinned open.
        /// - Returns: The list.
        private func cards(
            _ exercises: [SessionExercise], expansion: [UUID: Bool]
        ) -> some View {
            SessionExerciseList(
                exercises: exercises,
                expansion: .constant(expansion),
                warmupExpansion: .constant([:]),
                move: { _, _ in },
                unit: .kilograms,
                previous: PreviousPerformances(),
                personalRecords: SessionRecordMarks(),
                logSet: { _ in },
                mark: { _, _ in },
                markCompleted: { _, _ in },
                edit: { _ in },
                markDone: { _, _ in },
                logPlanned: { _ in }
            )
        }

        /// The editor as an adjustment opens it: the target line, then the form.
        ///
        /// **Composed rather than rendered as ``SetEditorView``**, for the reason
        /// `SessionSnapshotTests`' own editor helper is composed — `ImageRenderer` lays a
        /// `ScrollView`'s content out and draws none of it, so a picture of the sheet is a picture
        /// of the target line and the two commands with the whole form missing.
        ///
        /// **The order, the spacing and both of the target line's paddings are the sheet's own**,
        /// copied from ``SetEditorView`` rather than chosen here: this reference exists to make a
        /// claim about where that line sits, so a composition that spaced it differently would
        /// picture a screen nobody ships. The commands read their state off the draft for the same
        /// reason — hardcoded, they would keep drawing a loggable form over one that stopped being
        /// loggable.
        private var adjustingEditor: some View {
            let draft = Fixtures.editedDraft
            return VStack(spacing: Spacing.sm.points) {
                PlannedTargetLine(
                    target: PlanFixtures.prescription, comparison: nil, unit: .kilograms
                )
                .padding(.horizontal, Spacing.lg.points)
                .padding(.top, Spacing.lg.points)
                SetEditorFields(
                    draft: .constant(draft),
                    hasInput: .constant(true),
                    isEditing: true,
                    vocabulary: Fixtures.vocabulary,
                    equipment: Fixtures.equipment
                )
                .padding(Spacing.lg.points)
                SetEditorCommands(
                    isLoggable: draft.isLoggable,
                    showsRefusal: !draft.isLoggable && !draft.isBlank,
                    isEditing: true,
                    log: {},
                    cancel: {},
                    delete: {}
                )
            }
        }
    }

#endif
