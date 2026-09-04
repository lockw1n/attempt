#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 and DOD-16.3 for what a resumed workout opens on. A file of its own on
    // `SessionSnapshotFixtures`' argument: the two suites beside it are at `file_length` already,
    // and this one grows with the screen's *layout* rather than with its components.
    //
    // WHY THE COMPOSITION IS RESTATED HERE. `ActiveSessionView` owns a `.task` that reads a store,
    // and `ImageRenderer` has no way to run one — so the screen itself has never been the subject of
    // a reference in this package. What is restated below is only the stacking: every piece is the
    // screen's own type, with the screen's own spacing tokens, so a component that changes shape
    // moves these references. A piece the screen adds and this file does not would not, which is
    // what the simulator run is for (`docs/phase-1/tasks.md` §2).

    @MainActor
    @Suite("What a resumed workout opens on")
    struct SessionAboveFoldSnapshotTests {
        // MARK: - The first screen (FR-16.6.1, NFR-16.3, DOD-16.3)

        @Test func freshWorkout() throws {
            // A workout just started: nothing logged, no plan behind it, and the first card open
            // with nothing in it. The progress header is drawn because the workout has exercises —
            // over an empty one the screen draws none, which is `SessionProgressHeader`'s own rule.
            try assertSnapshots(named: "Session-above-fold-fresh") {
                fixedEnvironment {
                    aboveTheFold(
                        adherence: nil,
                        exercises: [Fixtures.exercises[3]]
                    )
                }
            }
        }

        @Test func resumedWorkout() throws {
            // The same head with a workout in progress behind it: the progress bar part-filled, and
            // the summary line carrying both its facts — the start time and `FR-15.3.3`'s adherence
            // — which is the case that puts `SessionSummaryLine`'s `ViewThatFits` to work.
            //
            // The planned fixtures, so the figure and the cards are the same workout: adherence read
            // off some other list would be a number this picture cannot be checked against.
            //
            // TWO OF THEM, and the cut is not a shortcut. `ImageRenderer` hands back a blank image
            // past about 7k pixels of height, and the harness compares dimensions before pixels —
            // so a taller subject records a blank reference that matches a blank render forever.
            // Caught here by hashing the light and dark pair, which were identical at
            // `accessibility3`. What this reference claims is the HEAD — the part-filled bar and
            // the two-fact line — and the cards below it are already pictured by `Session-cards`,
            // so nothing is lost with them; one done and one not is what the bar and the figure
            // need.
            let planned = Array((PlanFixtures.deviations + PlanFixtures.completion).prefix(2))
            try assertSnapshots(named: "Session-above-fold-resumed") {
                fixedEnvironment {
                    aboveTheFold(adherence: SessionAdherence(planned), exercises: planned)
                }
            }
        }

        @Test func theFirstSetRowIsInsideTheFirstScreen() throws {
            // DOD-16.3, asserted on the rendering's own height rather than by eye.
            //
            // THE BUDGET. The smallest device this app supports is the one with the smallest screen
            // still running its deployment target: 375 × 667 pt. A pushed screen loses the status
            // bar (20 pt) and an inline navigation bar (44 pt) off the top, which leaves 603 pt of
            // content — and nothing off the bottom, that device having a home button rather than a
            // home indicator.
            //
            // WHY THE MEASUREMENT IS CONSERVATIVE, twice over. The harness renders at 320 pt rather
            // than 375, so every label here has less width and more of them wrap; and the card in
            // the subject carries TWO set rows, so what is measured runs past the first one to the
            // bottom of the second. Both make the number larger than the screen's, which is the
            // direction that keeps a pass meaningful.
            let budget = 603.0
            let rendered = try Snapshot.render(
                fixedEnvironment { aboveTheFold(adherence: nil, exercises: [Fixtures.exercises[0]]) },
                appearance: .light,
                typeSize: .default
            )
            let points = Double(rendered.height) / Snapshot.scale
            print("DOD-16.3 above-the-fold height: \(points) pt against a \(budget) pt budget")
            #expect(points < budget)
        }

        // MARK: - The foot: FR-1.2.9's note, folded beside Finish (FR-16.6.1)

        @Test func notesFoldedOverANote() throws {
            // A workout that has been noted, as the screen leaves it: folded, with the note's first
            // line on the header. That line is the whole of what the fold costs a lifter who wants
            // to read a note back — the reason `FR-16.6.1` can put the editor at the foot at all.
            try assertSnapshots(named: "Session-notes") {
                fixedEnvironment {
                    SessionNotesFold(
                        draft: .constant(Fixtures.storedNote),
                        isExpanded: .constant(false),
                        hasFailed: false,
                        save: {}
                    )
                }
            }
        }

        @Test func notesFoldedOverNothing() throws {
            // The commoner case, and its own reference rather than a variant: with no note there is
            // no second line, and a header that reserved room for one would put the fold's cost back
            // on every workout that never has one.
            try assertSnapshots(named: "Session-notes-empty") {
                fixedEnvironment {
                    SessionNotesFold(
                        draft: .constant(SessionNoteDraft()),
                        isExpanded: .constant(false),
                        hasFailed: false,
                        save: {}
                    )
                }
            }
        }

        @Test func notesOpenUnsavedAndFailed() throws {
            // The fold open, over an edit that has not been stored and a write that failed: the
            // field, **Save note**, **Discard changes** and the shared error under them. All three
            // in one reference because none moves the others, and because what is worth checking is
            // that they still fit at accessibility3, where `ViewThatFits` drops the two commands
            // into a column.
            //
            // It is also the one reference that shows the note's failure banner INSIDE the fold,
            // which is what keeps it apart from `SessionCommandsSection`'s own at the same foot.
            try assertSnapshots(named: "Session-notes-editing") {
                fixedEnvironment {
                    SessionNotesFold(
                        draft: .constant(Fixtures.editedNote),
                        isExpanded: .constant(true),
                        hasFailed: true,
                        save: {}
                    )
                }
            }
        }

        /// Everything `ActiveSessionView` draws above the first exercise's set rows, stacked the way
        /// that screen stacks it.
        ///
        /// - Parameters:
        ///   - adherence: `FR-15.3.3`'s figure, or `nil` where nothing was prescribed.
        ///   - exercises: The workout's exercises. The first one's card is what the set row is in.
        /// - Returns: The head of the screen.
        @ViewBuilder private func aboveTheFold(
            adherence: SessionAdherence?,
            exercises: [SessionExercise]
        ) -> some View {
            LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xl.points) {
                        SessionSummaryLine(session: Fixtures.session, adherence: adherence)
                        VStack(alignment: .leading, spacing: Spacing.md.points) {
                            Text(LoggingStrings.sessionExercisesSection)
                                .font(Typography.sectionHeading.font)
                                .foregroundStyle(ColorToken.textPrimary)
                            SessionExerciseList(
                                exercises: exercises,
                                expansion: .constant([:]),
                                warmupExpansion: .constant([:]),
                                groupExpansion: .constant([]),
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.lg.points)
                } header: {
                    SessionProgressHeader(progress: SessionProgress(exercises))
                }
            }
        }
    }

#endif
