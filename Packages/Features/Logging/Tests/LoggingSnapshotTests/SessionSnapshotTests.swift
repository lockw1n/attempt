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

    /// Pins the process time zone, so a rendered date is the same picture on a developer's machine as
    /// it is on the CI runner.
    ///
    /// **A reference that renders a date is otherwise not reproducible**, and the failure is
    /// asymmetric: recorded in `EDT` and compared in `UTC`, a time renders four hours out and every
    /// such reference fails on CI alone. `AppFormat`'s styles take a locale and read the process's
    /// time zone, so the locale is pinned per subject below and this is the other half.
    private let pinnedTimeZone: Bool = {
        NSTimeZone.default = TimeZone(identifier: "UTC") ?? .gmt
        return true
    }()

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
                        move: { _, _ in },
                        unit: .kilograms,
                        logSet: { _ in }
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
                fixedEnvironment {
                    SetEditorSheet(
                        draft: SetDraft(unit: .kilograms, locale: Fixtures.locale),
                        log: { _ in },
                        cancel: {}
                    )
                }
            }
        }

        @Test func setEditorRepeating() throws {
            // FR-1.2.6, and the picture that matters most: the form as **Repeat set** opens it,
            // filled in from the last set with the confirming command live. What is being checked
            // is that the ± controls and the fields all still fit at NFR-1.10's ceiling — this is
            // the screen NFR-1.4 and NFR-1.3 both name.
            try assertSnapshots(named: "Session-set-editor-repeat") {
                fixedEnvironment {
                    SetEditorSheet(
                        draft: SetDraft(
                            repeating: SetEntryValues(
                                weight: Weight(grams: 102_500), reps: 5, rpe: 8),
                            unit: .kilograms,
                            locale: Fixtures.locale
                        ),
                        log: { _ in },
                        cancel: {}
                    )
                }
            }
        }

        @Test func setEditorRefusing() throws {
            // A draft that does not resolve: the RPE is outside 1...10, which is the one range this
            // form checks and the record deliberately does not. The message renders beside the
            // command rather than under the field, so it is in the same place whichever field is
            // wrong.
            try assertSnapshots(named: "Session-set-editor-invalid") {
                fixedEnvironment {
                    SetEditorSheet(draft: Fixtures.refusingDraft, log: { _ in }, cancel: {})
                }
            }
        }

        @Test func loggedSets() throws {
            // One card's worth of logged sets, with and without a rating. The multiplication sign
            // between the two numerals is drawn and hidden from VoiceOver; what a reference can
            // check is that the line still reads as one set at NFR-1.10's ceiling rather than
            // wrapping into three.
            try assertSnapshots(named: "Session-set-rows") {
                fixedEnvironment {
                    VStack(alignment: .leading) {
                        ForEach(Array(Fixtures.loggedSets.enumerated()), id: \.element.id) { pair in
                            SetRow(set: pair.element, position: pair.offset + 1, unit: .kilograms)
                        }
                    }
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

        /// A subject whose rendering depends on a locale or a time zone, pinned to both.
        ///
        /// The locale is the environment's, which is what `AppFormat` reads through the view; the
        /// time zone is the process's, pinned once above.
        private func fixedEnvironment(@ViewBuilder _ subject: () -> some View) -> some View {
            _ = pinnedTimeZone
            return subject()
                .environment(\.locale, Fixtures.locale)
                .environment(\.timeZone, .gmt)
        }
    }

    /// The workout these references render, and the two things it takes to render one.
    enum Fixtures {
        /// The locale every reference here renders and parses numbers in.
        static let locale = Locale(identifier: "en_US_POSIX")

        /// A draft the form refuses: the load and the reps resolve, the rating does not.
        static var refusingDraft: SetDraft {
            var draft = SetDraft(unit: .kilograms, locale: locale)
            draft.weightText = "102.5"
            draft.repsText = "5"
            draft.rpeText = "18"
            return draft
        }

        /// Two logged sets, one rated and one not.
        static let loggedSets: [SetEntry] = [
            loggedSet(index: 0, weight: Weight(grams: 102_500), reps: 5, rpe: 8),
            loggedSet(index: 1, weight: Weight(grams: 102_500), reps: 3, rpe: nil),
        ]

        /// One logged set, with every identifier and timestamp fixed.
        private static func loggedSet(
            index: Int, weight: Weight, reps: Int, rpe: Double?
        ) -> SetEntry {
            SetEntry(
                id: identifier("E\(index)"),
                createdAt: startedAt,
                updatedAt: startedAt,
                deletedAt: nil,
                entryID: identifier("B1"),
                order: index,
                weight: weight,
                reps: reps,
                rpe: rpe,
                rir: nil,
                isWarmup: false,
                isCompleted: true,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: startedAt
            )
        }

        /// A gregorian calendar in UTC, so the fixed day below is the same instant everywhere.
        private static let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            return calendar
        }()

        /// The training day, at its start — where `ActiveSessionStore.start(on:)` puts it.
        static let day =
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 14)) ?? .distantPast

        /// Mid-evening, so the rendered time is unambiguous rather than sitting near a boundary.
        static let startedAt =
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 18, minute: 42))
            ?? .distantPast

        /// One workout in progress, with every field fixed so a rendering never moves.
        static let session = WorkoutSession(
            id: UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-0000000000A1") ?? UUID(),
            createdAt: startedAt,
            updatedAt: startedAt,
            deletedAt: nil,
            date: day,
            startedAt: startedAt,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )

        /// Three exercises in one workout, at the three shapes a card has: unstarted, part-done and
        /// finished. Every identifier and timestamp is fixed so a rendering never moves.
        static let exercises: [SessionExercise] = [
            sessionExercise(
                index: 1,
                name: "Back Squat",
                sets: [(isWarmup: false, isCompleted: true), (isWarmup: false, isCompleted: true)]
            ),
            sessionExercise(
                index: 2,
                name: "Bench Press",
                sets: [(isWarmup: true, isCompleted: true), (isWarmup: false, isCompleted: false)]
            ),
            sessionExercise(index: 3, name: "Romanian Deadlift", sets: []),
        ]

        /// One card's worth of workout.
        private static func sessionExercise(
            index: Int,
            name: String,
            sets: [(isWarmup: Bool, isCompleted: Bool)]
        ) -> SessionExercise {
            let entryID = identifier("B\(index)")
            let exerciseID = identifier("C\(index)")
            return SessionExercise(
                entry: ExerciseEntry(
                    id: entryID,
                    createdAt: startedAt,
                    updatedAt: startedAt,
                    deletedAt: nil,
                    sessionID: session.id,
                    exerciseID: exerciseID,
                    order: index - 1,
                    notes: ""
                ),
                exercise: Exercise(
                    id: exerciseID,
                    createdAt: startedAt,
                    updatedAt: startedAt,
                    deletedAt: nil,
                    name: name,
                    movement: .squat,
                    parentExerciseID: nil,
                    equipment: .barbell,
                    laterality: .bilateral,
                    barType: .standard,
                    implementCount: 1,
                    isCustom: false,
                    isArchived: false,
                    notes: ""
                ),
                sets: sets.enumerated().map { position, flags in
                    SetEntry(
                        id: identifier("D\(index)\(position)"),
                        createdAt: startedAt,
                        updatedAt: startedAt,
                        deletedAt: nil,
                        entryID: entryID,
                        order: position,
                        weight: Weight(grams: 100_000),
                        reps: 5,
                        rpe: nil,
                        rir: nil,
                        isWarmup: flags.isWarmup,
                        isCompleted: flags.isCompleted,
                        targetWeight: nil,
                        targetReps: nil,
                        modifiers: [],
                        notes: "",
                        completedAt: nil
                    )
                }
            )
        }

        /// A fixed identifier, so nothing in these renderings depends on a fresh `UUID`.
        private static func identifier(_ suffix: String) -> UUID {
            let padded = String(suffix.prefix(4)).padding(toLength: 4, withPad: "0", startingAt: 0)
            return UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-00000000\(padded)") ?? UUID()
        }

        /// A preference in a named position, over storage no other test can see.
        ///
        /// **A fresh suite each time, removed as soon as it has been read.** A fixed name would
        /// outlive the run and be inherited by the next one — harmless to a rendering that does not
        /// draw the control, and exactly the kind of leftover that makes a later test lie.
        ///
        /// - Parameter isEnabled: Which position to build. It does not reach the rendering — see the
        ///   note on the suite — but a preference built at random would still be the wrong subject.
        /// - Returns: The preference.
        static func preference(isEnabled: Bool) -> ScreenWakePreference {
            let name = "snapshots.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: name) else {
                return ScreenWakePreference(defaults: .standard)
            }
            defaults.set(isEnabled, forKey: "logging.screen-wake.enabled")
            let preference = ScreenWakePreference(defaults: defaults)
            defaults.removePersistentDomain(forName: name)
            return preference
        }
    }

#endif
