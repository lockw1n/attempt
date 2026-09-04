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
            // The same head with a workout in progress behind it, and the case that puts
            // `SessionSummaryLine`'s `ViewThatFits` to work: the summary line carrying BOTH its
            // facts — the start time and `FR-15.3.3`'s adherence — over a card that came from a
            // plan.
            //
            // The planned fixtures, so the figure and the card are the same workout: adherence read
            // off some other list would be a number this picture cannot be checked against.
            //
            // ONE CARD, and the cut costs this reference no claim it was the only one making.
            // `ImageRenderer` hands back a blank image past roughly 7k pixels of height and the
            // harness compares dimensions before pixels, so a reference that crosses it records a
            // blank that matches a blank render forever — and two cards put `accessibility3` at
            // 6,814, thirty pixels under the tallest height anything here has been proven to
            // render. The bar over a longer list is `Session-progress`'s claim and the cards below
            // are `Session-cards`', both of which exist; what is left here is the stack, which one
            // card shows as well as two.
            let planned = Array((PlanFixtures.deviations + PlanFixtures.completion).prefix(1))
            try assertSnapshots(named: "Session-above-fold-resumed") {
                fixedEnvironment {
                    aboveTheFold(adherence: SessionAdherence(planned), exercises: planned)
                }
            }
        }

        @Test func theFirstSetRowIsInsideTheFirstScreen() throws {
            // DOD-16.3, asserted on the rendering's own height rather than by eye.
            //
            // THE SUBJECT HAS TO BE A CARD THAT OPENS, and this is the trap the measurement walks
            // into otherwise. `SessionExerciseList` draws a card with `isExpanded:` defaulted to
            // `!item.isDone`, so an exercise whose working sets are all completed renders as a
            // header and nothing else — no set row at all, and a budget assertion over it measures
            // a heading. `Fixtures.exercises[1]` is the resumed shape instead: warmups done and
            // folded into their group, the first working set logged and not completed, so `isDone`
            // is false, the card is open, and there is a set row in the picture to be inside the
            // screen. Measured, on the same assertion: `exercises[0]` reads 296 pt and `exercises[1]`
            // 560 pt — 264 pt of a card that never opened.
            //
            // THE BUDGET. The smallest device this app supports is the one with the smallest screen
            // still running its deployment target: 375 × 667 pt. This screen is pushed into a
            // `NavigationStack` inside `RootTabView`'s `TabView` and hides nothing, so it loses the
            // status bar (20 pt), an inline navigation bar (44 pt) AND the tab bar (49 pt) — that
            // device having a home button rather than a home indicator, so the tab bar is its full
            // 49 and there is no inset under it.
            //
            // WHAT IS SUBTRACTED FROM THE MEASUREMENT. `Snapshot.render` pads every subject by
            // `Spacing.lg` on all four sides; the screen has no such padding above its progress bar
            // or below its last card, so the vertical 32 pt is the harness's and not the screen's.
            // The horizontal 32 pt is left where it is, and is the reason this stays conservative:
            // it renders the content 32 pt narrower than the device would, so more labels wrap here
            // than there and the height comes out larger than the screen's. So does measuring to the
            // bottom of the whole card rather than to the bottom of its first set row.
            let budget = 667.0 - 20.0 - 44.0 - 49.0
            let rendered = try Snapshot.render(
                fixedEnvironment { aboveTheFold(adherence: nil, exercises: [Fixtures.exercises[1]]) },
                appearance: .light,
                typeSize: .default
            )
            let points = Double(rendered.height) / Snapshot.scale - 2 * Spacing.lg.points
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
