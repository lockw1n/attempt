#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for this module's two screens, in four configurations each — light and dark (`G-7.1`),
    // default and `accessibility3` (`NFR-1.10`'s own ceiling).
    //
    // WHAT IS RENDERED AND WHAT IS NOT. The sections, not `TrainingHomeView` or `ActiveSessionView`
    // themselves: both own a `.task` that reads a store, and `ImageRenderer` has no way to run one.
    // Between them these references cover every pixel the two screens have of their own — the workout
    // in progress, its facts, the two commands that end it, the screen-wake control, the date control
    // and the four placeholders either screen can show instead.
    //
    // TWO THINGS THESE REFERENCES CANNOT SHOW, both measured rather than assumed. A `NavigationLink`
    // with no `NavigationStack` above it draws as though it led nowhere, so its label is dimmer here
    // than in the app — and wrapping the subject in one makes it worse, a `NavigationStack` being
    // UIKit-backed itself. And a UIKit-backed control does not rasterise at all: `DatePicker` and
    // `Toggle` are drawn as the renderer's unsupported-view placeholder, so what the two references
    // holding one check is the label, the copy and the layout around it — never the control's own
    // position. These are a regression baseline; the colours and the controls are what the simulator
    // run checks (`docs/phase-1/tasks.md` §2).
    //
    // THE COPY HERE IS THE REAL COPY, on the exercise library's rule: a screen's words are part of
    // what it renders. What stays out of the copy is the data — a workout's date is a record's field,
    // and it is rendered through `AppFormat` exactly as the screen renders it.

    @MainActor
    @Suite("Session lifecycle snapshots")
    struct SessionSnapshotTests {
        // MARK: - Train root (FR-1.2.1, FR-1.2.11, FR-1.13.2)

        @Test func workoutInProgress() throws {
            try assertSnapshots(named: "Train-in-progress") {
                fixedEnvironment {
                    SessionInProgressSection(session: Fixtures.session)
                }
            }
        }

        @Test func noWorkoutYet() throws {
            // FR-1.13.2's first-launch state. The action is part of the picture: a state that named
            // the way to a first workout without offering it is the dead end the requirement is
            // about.
            try assertSnapshots(named: "Train-empty") {
                EmptyStateView(
                    symbolName: "figure.strengthtraining.traditional",
                    headline: Text(LoggingStrings.trainEmptyHeadline),
                    message: Text(LoggingStrings.trainEmptyMessage),
                    action: StateAction(Text(LoggingStrings.trainStartAction)) {}
                )
            }
        }

        @Test func workoutDate() throws {
            try assertSnapshots(named: "Train-date") {
                fixedEnvironment {
                    WorkoutDateSection(day: .constant(Fixtures.day))
                }
            }
        }

        @Test func screenWake() throws {
            // One position, not both: the switch is UIKit-backed and rasterises as a placeholder, so
            // a second reference with the preference off would be the same picture. What this checks
            // is that the label and its sentence stay legible beside a control-sized hole —
            // `NFR-1.10`'s ceiling is where that stops being obvious.
            try assertSnapshots(named: "Train-screen-wake") {
                ScreenWakeSection(preference: Fixtures.preference(isEnabled: true))
            }
        }

        @Test func readFailed() throws {
            try assertSnapshots(named: "Train-error") {
                ErrorStateView(
                    headline: Text(LoggingStrings.trainErrorHeadline),
                    message: Text(LoggingStrings.trainErrorMessage),
                    retry: {}
                )
            }
        }

        @Test func startFailed() throws {
            // A failed *write*, and a different picture from the one above on purpose: no headline
            // and no retry button, because it renders between the start command and the date
            // control rather than in place of them, and the retry is that command itself.
            try assertSnapshots(named: "Train-start-error") {
                ErrorStateView(message: Text(LoggingStrings.trainStartErrorMessage))
            }
        }

        // MARK: - The workout in progress (FR-1.2.11, FR-1.2.12)

        @Test func workoutSummary() throws {
            try assertSnapshots(named: "Session-summary") {
                fixedEnvironment {
                    SessionSummarySection(session: Fixtures.session)
                }
            }
        }

        @Test func commands() throws {
            try assertSnapshots(named: "Session-commands") {
                SessionCommandsSection(hasFailed: false, finish: {}, discard: {})
            }
        }

        @Test func commandsAfterAFailedWrite() throws {
            // The workout is still on screen beside the failure, which is the part worth a picture:
            // a failed write costs this screen nothing.
            try assertSnapshots(named: "Session-commands-failed") {
                SessionCommandsSection(hasFailed: true, finish: {}, discard: {})
            }
        }

        @Test func noExercisesYet() throws {
            // The action is FR-1.2.2's chooser, and it is part of the picture: a workout with
            // nothing in it whose only way forward was a sentence is the dead end FR-1.13.2 is
            // about.
            try assertSnapshots(named: "Session-empty") {
                EmptyStateView(
                    symbolName: "list.bullet.rectangle",
                    headline: Text(LoggingStrings.sessionEmptyHeadline),
                    message: Text(LoggingStrings.sessionEmptyMessage),
                    action: StateAction(Text(LoggingStrings.sessionAddExerciseAction)) {}
                )
            }
        }

        // MARK: - The workout's exercises (FR-1.2.2, FR-1.2.13)

        @Test func exerciseCards() throws {
            // FR-1.2.13's vertical card list, at the three shapes a card has: open with nothing in
            // it, open with sets, and a finished exercise folded up. The ends of the list are part
            // of it too — the first card's "move up" and the last card's "move down" are drawn
            // disabled rather than hidden.
            try assertSnapshots(named: "Session-cards") {
                fixedEnvironment {
                    SessionExerciseList(
                        exercises: Fixtures.exercises,
                        expansion: .constant([:]),
                        warmupExpansion: .constant([:]),
                        move: { _, _ in },
                        unit: .kilograms,
                        previous: Fixtures.previousPerformances,
                        logSet: { _ in },
                        mark: { _, _ in },
                        markCompleted: { _, _ in },
                        edit: { _ in }
                    )
                }
            }
        }

        // MARK: - Sets inside one exercise (FR-1.2.3, FR-1.2.6)

        @Test func setEditorBlank() throws {
            // FR-1.2.3's form as **Add set** opens it: four fields, nothing filled in, and the
            // confirming command disabled. No complaint yet — a form that opened saying what is
            // wrong with it is a form scolding the user for not having typed.
            try assertSnapshots(named: "Session-set-editor-blank") {
                fixedEnvironment { editor(over: SetDraft(unit: .kilograms, locale: Fixtures.locale)) }
            }
        }

        @Test func setEditorRepeating() throws {
            // FR-1.2.6: the form as **Repeat set** opens it, with the confirming command live
            // rather than dimmed. What is being checked is that the labels, the hints and the four
            // ± controls all still fit at NFR-1.10's ceiling — this is the screen NFR-1.4 and
            // NFR-1.3 both name.
            try assertSnapshots(named: "Session-set-editor-repeat") {
                fixedEnvironment { editor(over: Fixtures.repeatedDraft) }
            }
        }

        @Test func setEditorWarmup() throws {
            // FR-1.2.4's fifth row in its ON position. Its own reference rather than a variant of
            // the one above, because it is the one state a reference here can actually check: the
            // control is a button rather than a switch, so unlike every `TextField` around it it
            // rasterises — and G-4.5's claim that on and off differ by a symbol and not only by
            // colour is exactly what a picture settles.
            try assertSnapshots(named: "Session-set-editor-warmup") {
                fixedEnvironment { editor(over: Fixtures.warmupDraft) }
            }
        }

        @Test func setEditorRefusing() throws {
            // A draft that does not resolve: the RPE is outside 1...10, which is the one range this
            // form checks and the record deliberately does not. The message renders beside the
            // command rather than under the field, so it is in the same place whichever field is
            // wrong. Its own reference rather than a variant of the blank one — and that is worth
            // saying, because the two were byte-identical before the form became renderable.
            try assertSnapshots(named: "Session-set-editor-invalid") {
                fixedEnvironment { editor(over: Fixtures.refusingDraft) }
            }
        }

        @Test func setEditorEditing() throws {
            // FR-1.2.7: the same five fields, opened over a set that already exists. Its own
            // reference because three things differ and all three are drawn — the title, the
            // confirming command's words, and the deletion, which is offered only here. The
            // deletion is also the one control G-4.5 is about on this sheet: destructive is carried
            // by a glyph as well as by the tint.
            try assertSnapshots(named: "Session-set-editor-edit") {
                fixedEnvironment { editor(over: Fixtures.editedDraft, isEditing: true) }
            }
        }

        // MARK: - Modifiers (FR-1.2.8)

        @Test func setEditorWithModifiers() throws {
            // The row in its filled-in state: the summary is a locale-aware list, and the third
            // term is a spelling this build does not recognise — drawn as itself, which is the
            // whole of OpenVocabulary's preservation reaching a screen. Its own reference because
            // the row is one line when empty and wraps when it is not, and NFR-1.10's ceiling is
            // where that stops being free.
            try assertSnapshots(named: "Session-set-editor-modifiers") {
                fixedEnvironment { editor(over: Fixtures.modifiedDraft) }
            }
        }

        @Test func modifierPicker() throws {
            // FR-1.2.8's multi-select. Two things a picture settles: applied and not applied differ
            // by a checkmark and not only by a tint (G-4.5), and the unlisted term carries its own
            // note rather than being indistinguishable from an offered one.
            let applied = [
                SetModifier(.belt), SetModifier(rawValue: "reverse band"), Fixtures.unlisted,
            ]
            let vocabulary = Fixtures.vocabulary
            try assertSnapshots(named: "Session-modifier-picker") {
                fixedEnvironment {
                    SetModifierSelection(
                        rows: vocabulary.offered(with: applied),
                        applied: applied,
                        isOffered: { vocabulary.terms.contains($0) },
                        toggle: { _ in },
                        destination: { EmptyView() }
                    )
                }
            }
        }

        @Test func modifierListEditor() throws {
            // The list itself: the hint that says editing it leaves logged sets alone, the add
            // field, the user's own terms with their removals, and the nine that have neither.
            // What a reference checks here is that the two sections stay told apart at
            // accessibility3, where every row is taller than the heading above it.
            try assertSnapshots(named: "Session-modifier-list") {
                fixedEnvironment {
                    SetModifierListFields(vocabulary: Fixtures.vocabulary)
                }
            }
        }

        @Test func setRowsWithModifiers() throws {
            // FR-1.2.8 on the row rather than only in the editor. The line the modifiers take is a
            // second one under the values at every size, so what this checks is that it does not
            // come out of the load — which is the budget T-1.23 measured a 44pt badge spending.
            try assertSnapshots(named: "Session-set-rows-modifiers") {
                fixedEnvironment { rows(Fixtures.modifiedSets) }
            }
        }

        @Test func loggedSets() throws {
            // One card's worth of logged sets, with and without a rating. The multiplication sign
            // between the two numerals is drawn and hidden from VoiceOver; what a reference can
            // check is that the line still reads as one set at NFR-1.10's ceiling rather than
            // wrapping into three — which is the budget FR-1.2.4's badge spends into, the number
            // having become a 44pt control.
            try assertSnapshots(named: "Session-set-rows") {
                fixedEnvironment { rows(Fixtures.loggedSets) }
            }
        }

        @Test func warmupsAndWorkingSets() throws {
            // FR-1.2.14, and the reference the requirement is actually about: two warmups numbered
            // W1, W2 beside three working sets numbered 1, 2, 3, with the warmups one step down the
            // type scale and one step back in the colour ramp. The two sequences and the
            // de-emphasis are both things only a picture checks — the numbers themselves are
            // `SetNumberingTests`'.
            try assertSnapshots(named: "Session-set-rows-warmup") {
                fixedEnvironment { rows(Fixtures.rampedSets) }
            }
        }

        @Test func failedSets() throws {
            // FR-1.2.5, and the reference G-4.5 is actually about: the failed rows are red, and the
            // glyph at the end of each row says the same thing in a shape that survives a
            // monochrome rendering. It also pictures the rule where the two de-emphases meet — a
            // failed warmup is red rather than quiet.
            try assertSnapshots(named: "Session-set-rows-failed") {
                fixedEnvironment { rows(Fixtures.failedSets) }
            }
        }

        @Test func setRowKeepsItsLineAtTheWidestHorizontalSize() throws {
            // NFR-1.10 names `accessibility3` and the references above picture it — but the row only
            // STACKS at accessibility sizes, so the tightest LINE it ever draws is `.xxxLarge`, one
            // step below that switch, and no reference renders there. T-1.23 measured a single 44pt
            // badge breaking `102.5 kg` into three lines; FR-1.2.5's outcome control is a second
            // one, so the horizontal budget lost another 44 points and the size nothing pictures is
            // the size most likely to have spent it.
            //
            // Rendered rather than referenced, because what is checked is a number and not an
            // appearance: a row whose load wraps is taller than the same row whose load does not.
            // Both controls are needed — the narrow load says the subject's height came from
            // fitting, and the absurd one says this measurement can tell a wrap apart at all.
            func height(of sets: [SetEntry]) throws -> Int {
                try Snapshot.render(
                    fixedEnvironment { rows(sets) }.dynamicTypeSize(.xxxLarge),
                    appearance: .light,
                    typeSize: .default
                ).height
            }
            let wide = try height(of: Fixtures.widestLoad)

            #expect(wide == (try height(of: Fixtures.narrowestLoad)))
            #expect(wide < (try height(of: Fixtures.wrappingLoad)))
        }

        @Test func warmupGroupOpen() throws {
            try assertSnapshots(named: "Session-warmup-header-open") {
                fixedEnvironment {
                    WarmupSectionHeader(count: 2, isExpanded: true, toggle: {})
                }
            }
        }

        @Test func warmupGroupFolded() throws {
            // Its own reference rather than a variant: folded is the state the group is in for most
            // of a workout, and the count beside the heading is the only thing then saying how many
            // rows are rolled up.
            try assertSnapshots(named: "Session-warmup-header-folded") {
                fixedEnvironment {
                    WarmupSectionHeader(count: 2, isExpanded: false, toggle: {})
                }
            }
        }

        @Test func sessionProgress() throws {
            // Drawn rather than a `ProgressView`, so the bar's fill is something the gate can see —
            // see the header's own note.
            try assertSnapshots(named: "Session-progress") {
                fixedEnvironment {
                    SessionProgressHeader(progress: SessionProgress(Fixtures.exercises))
                }
            }
        }

        @Test func exercisesReadFailed() throws {
            try assertSnapshots(named: "Session-exercises-error") {
                ErrorStateView(
                    headline: Text(LoggingStrings.sessionExercisesErrorHeadline),
                    message: Text(LoggingStrings.sessionExercisesErrorMessage),
                    retry: {}
                )
            }
        }

        @Test func sessionReadFailed() throws {
            // The state below says the workout is gone; this one says we could not tell. They are
            // the same absence to the screen and opposite facts to the user, so both are pictured —
            // and this is the one that carries a retry.
            try assertSnapshots(named: "Session-error") {
                ErrorStateView(
                    headline: Text(LoggingStrings.sessionErrorHeadline),
                    message: Text(LoggingStrings.sessionErrorMessage),
                    retry: {}
                )
            }
        }

        @Test func workoutNoLongerInProgress() throws {
            // No retry: reading again resolves to the same absence.
            try assertSnapshots(named: "Session-ended") {
                ErrorStateView(
                    headline: Text(LoggingStrings.sessionEndedHeadline),
                    message: Text(LoggingStrings.sessionEndedMessage)
                )
            }
        }

        /// A column of set rows, numbered the way the card numbers them.
        ///
        /// - Parameter sets: The sets, in the order they were logged.
        /// - Returns: The rows.
        private func rows(_ sets: [SetEntry]) -> some View {
            VStack(alignment: .leading) {
                ForEach(SetNumbering.numbered(sets)) { numbered in
                    SetRow(
                        numbered: numbered,
                        unit: .kilograms,
                        mark: { _, _ in },
                        markCompleted: { _, _ in },
                        edit: { _ in }
                    )
                }
            }
        }

        /// The set editor's two halves, stacked the way the sheet stacks them.
        ///
        /// **The `ScrollView` between them is left out, and that is the gate rather than the
        /// screen.** `ImageRenderer` lays a scroll view's content out and draws none of it, so a
        /// reference taken over `SetEditorSheet` itself is a picture of the divider and the two
        /// commands with the whole form missing — which is what the first three of these were, two
        /// of them byte-identical to each other in all four configurations. Rendering the fields
        /// directly is what makes NFR-1.10's claim checkable.
        ///
        /// What these still cannot show is a field's *contents*: a `TextField` is UIKit-backed, so
        /// it rasterises as the renderer's placeholder the same way `DatePicker` and `Toggle` do
        /// above. What is compared is the labels, the hints, the ± controls, the refusal and which
        /// state the confirming command is in.
        ///
        /// - Parameters:
        ///   - draft: What the form is holding.
        ///   - isEditing: Whether it is open over a set that already exists (`FR-1.2.7`).
        /// - Returns: The editor, laid out for a reference.
        private func editor(over draft: SetDraft, isEditing: Bool = false) -> some View {
            VStack(spacing: Spacing.sm.points) {
                SetEditorFields(
                    draft: .constant(draft),
                    hasInput: .constant(true),
                    isEditing: isEditing,
                    vocabulary: Fixtures.vocabulary
                )
                .padding(Spacing.lg.points)
                SetEditorCommands(
                    isLoggable: draft.isLoggable,
                    showsRefusal: !draft.isLoggable && !draft.isBlank,
                    isEditing: isEditing,
                    log: {},
                    cancel: {},
                    delete: {}
                )
            }
        }
    }

#endif
