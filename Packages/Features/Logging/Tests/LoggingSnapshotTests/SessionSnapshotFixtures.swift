#if os(iOS)

    import Foundation
    import PowerliftingCore
    import RepositoryFakes
    import RepositoryInterface
    import SwiftUI

    @testable import Logging

    // The workout every reference in `SessionSnapshotTests` renders. A file of its own so neither it
    // nor the suite beside it runs into `file_length` — the two grow for different reasons, a
    // reference being added and a fixture shape being added.

    /// Pins the process time zone, so a rendered date is the same picture on a developer's machine
    /// as it is on the CI runner.
    ///
    /// **A reference that renders a date is otherwise not reproducible**, and the failure is
    /// asymmetric: recorded in `EDT` and compared in `UTC`, a time renders four hours out and every
    /// such reference fails on CI alone. `AppFormat`'s styles take a locale and read the process's
    /// time zone, so the locale is pinned per subject and this is the other half.
    private let pinnedTimeZone: Bool = {
        NSTimeZone.default = TimeZone(identifier: "UTC") ?? .gmt
        return true
    }()

    /// A subject whose rendering depends on a locale or a time zone, pinned to both.
    ///
    /// The locale is the environment's, which is what `AppFormat` reads through the view; the time
    /// zone is the process's, pinned once above. Here rather than on a suite because both suites in
    /// this target render dates.
    ///
    /// - Parameter subject: What to render.
    /// - Returns: The subject, pinned.
    func fixedEnvironment(@ViewBuilder _ subject: () -> some View) -> some View {
        _ = pinnedTimeZone
        return subject()
            .environment(\.locale, Fixtures.locale)
            .environment(\.timeZone, .gmt)
    }

    /// The workout these references render, and the two things it takes to render one.
    enum Fixtures {
        /// The locale every reference here renders and parses numbers in.
        static let locale = Locale(identifier: "en_US_POSIX")

        /// A draft as `FR-1.2.6`'s duplicate opens it, carrying the last set's three fields.
        static var repeatedDraft: SetDraft {
            SetDraft(
                repeating: SetEntryValues(
                    weight: Weight(grams: 102_500), reps: 5, rpe: 8, isWarmup: false),
                unit: .kilograms,
                locale: locale
            )
        }

        /// A draft of a warmup — `FR-1.2.4`'s row in its other position.
        static var warmupDraft: SetDraft {
            SetDraft(
                repeating: SetEntryValues(
                    weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true),
                unit: .kilograms,
                locale: locale
            )
        }

        /// A draft as `FR-1.2.7`'s editor opens it, carrying the note as well — which is the one
        /// field a duplicate drops and an edit must not.
        static var editedDraft: SetDraft {
            let set = SetEntryValues(
                weight: Weight(grams: 102_500), reps: 5, rpe: 8, isWarmup: false, notes: "belt on")
            return SetDraft(editing: set, unit: .kilograms, locale: locale)
        }

        /// A draft carrying `FR-1.2.8`'s modifiers — one built-in and one spelling this build does
        /// not recognise, which is the pair the row has to draw side by side.
        static var modifiedDraft: SetDraft {
            var draft = SetDraft(
                repeating: SetEntryValues(
                    weight: Weight(grams: 102_500), reps: 5, rpe: 8, isWarmup: false),
                unit: .kilograms,
                locale: locale
            )
            draft.modifiers = [
                SetModifier(.belt), SetModifier(.sleeves), SetModifier(rawValue: "reverse band"),
            ]
            return draft
        }

        /// A spelling neither the nine nor ``vocabulary`` offers — what a set logged by a newer
        /// version carries, and the row that has to say so.
        static let unlisted = SetModifier(rawValue: "chains")

        /// A plate-calculator store that has read nothing, which is the only state `ImageRenderer`
        /// can put the set editor's row in: the read is a `.task`, and the renderer runs none.
        ///
        /// What the editor's reference therefore compares is the row's *unread* line — which is a
        /// state the screen really has, on a first open before the local read answers.
        static var equipment: PlateCalculatorStore {
            let fakes = InMemoryRepositoryStack()
            return PlateCalculatorStore(repository: fakes.equipment, settings: fakes.settings)
        }

        /// The modifier list these references draw, in a suite nothing else can see.
        ///
        /// Removed from disk as soon as it has been read, on ``preference(isEnabled:)``' argument:
        /// a suite that outlived the run would be inherited by the next one.
        static var vocabulary: SetModifierVocabulary {
            let name = "snapshots.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: name) else {
                return SetModifierVocabulary(defaults: .standard)
            }
            defaults.set(["reverse band"], forKey: SetModifierVocabulary.key)
            let vocabulary = SetModifierVocabulary(defaults: defaults)
            defaults.removePersistentDomain(forName: name)
            return vocabulary
        }

        /// A draft the form refuses: the load and the reps resolve, the rating does not.
        static var refusingDraft: SetDraft {
            var draft = SetDraft(unit: .kilograms, locale: locale)
            draft.weightText = "102.5"
            draft.repsText = "5"
            draft.rpeText = "18"
            return draft
        }

        /// Two logged sets carrying `FR-1.2.8`'s modifiers — the second one a spelling this build
        /// does not recognise, drawn as itself rather than dropped.
        static let modifiedSets: [SetEntry] = [
            loggedSet(
                index: 0,
                weight: Weight(grams: 102_500),
                reps: 5,
                rpe: 8,
                modifiers: [SetModifier(.belt), SetModifier(.sleeves)]
            ),
            loggedSet(
                index: 1,
                weight: Weight(grams: 102_500),
                reps: 3,
                rpe: nil,
                modifiers: [SetModifier(rawValue: "reverse band")]
            ),
        ]

        /// Two logged sets, one rated and one not.
        static let loggedSets: [SetEntry] = [
            loggedSet(index: 0, weight: Weight(grams: 102_500), reps: 5, rpe: 8),
            loggedSet(index: 1, weight: Weight(grams: 102_500), reps: 3, rpe: nil),
        ]

        /// A ramp: two warmups and then the work, which is `FR-1.2.14`'s own example.
        static let rampedSets: [SetEntry] = [
            loggedSet(index: 2, weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true),
            loggedSet(index: 3, weight: Weight(grams: 80_000), reps: 3, rpe: nil, isWarmup: true),
            loggedSet(index: 4, weight: Weight(grams: 102_500), reps: 5, rpe: 8),
            loggedSet(index: 5, weight: Weight(grams: 102_500), reps: 5, rpe: 8.5),
            loggedSet(index: 6, weight: Weight(grams: 102_500), reps: 5, rpe: nil),
        ]

        /// `FR-1.2.5`'s outcome, pictured: a working set that fell short between two that did not,
        /// and a warmup that did too.
        ///
        /// The failed warmup is here because the two de-emphases meet on it — a warmup is drawn
        /// quieter and a failed set is drawn red, and which of them wins is a rule a picture is the
        /// only check on.
        static let failedSets: [SetEntry] = [
            loggedSet(
                index: 7,
                weight: Weight(grams: 60_000),
                reps: 5,
                rpe: nil,
                isWarmup: true,
                isCompleted: false
            ),
            loggedSet(index: 8, weight: Weight(grams: 102_500), reps: 5, rpe: 8),
            loggedSet(
                index: 9,
                weight: Weight(grams: 102_500),
                reps: 2,
                rpe: 10,
                isCompleted: false
            ),
        ]

        /// The same working set at three loads, for the width probe. Not a reference set — what they
        /// back is a *number* rather than an appearance.
        ///
        /// `102.5 kg` is the subject: the load T-1.23 measured breaking across three lines once the
        /// badge took 44 points out of the row.
        static let widestLoad: [SetEntry] = [
            loggedSet(index: 10, weight: Weight(grams: 102_500), reps: 5, rpe: 10)
        ]

        /// The negative control for ``widestLoad`` — the same row with a load too short to wrap, so
        /// a matching height means the subject did not wrap either.
        static let narrowestLoad: [SetEntry] = [
            loggedSet(index: 11, weight: Weight(grams: 60_000), reps: 5, rpe: 10)
        ]

        /// The positive control, and the half that makes the other two mean something: a load no
        /// lifter will ever enter, wide enough that it *must* take a second line. Without it, a
        /// measurement where everything wrapped equally would read as one where nothing did.
        static let wrappingLoad: [SetEntry] = [
            loggedSet(index: 12, weight: Weight(grams: 123_456_700), reps: 5, rpe: 10)
        ]

        /// `FR-1.2.10`'s previous session, as the strip draws it: a ramp and then three working
        /// sets, the last of them short of the other two.
        ///
        /// The warmup is here because the strip has to *not* draw it — a value that had dropped it
        /// could not picture the rule.
        static let previousPerformance = PreviousPerformance(
            date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 7)) ?? .distantPast,
            sets: [
                loggedSet(index: 20, weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true),
                loggedSet(index: 21, weight: Weight(grams: 100_000), reps: 5, rpe: 8),
                loggedSet(index: 22, weight: Weight(grams: 100_000), reps: 5, rpe: 8.5),
                loggedSet(index: 23, weight: Weight(grams: 100_000), reps: 3, rpe: 10),
            ]
        )

        /// The strips behind ``exercises``: two cards that have a previous session and one that has
        /// none.
        ///
        /// The unstarted card is the one with none, which is the case `FR-1.13.3` is drawn for; the
        /// finished card has one too, but it is folded, so the list pictures both states at once.
        static let previousPerformances = PreviousPerformances(
            byEntryID: [
                identifier("B2"): previousPerformance,
                identifier("B4"): previousPerformance,
            ],
            hasLoaded: true
        )

        /// `FR-1.6.3`'s badge, pictured on the rows.
        ///
        /// **One set holding one record and one holding five**, which is the pair the badge's label
        /// has to render: "Personal record for 3 reps" against "…for 1, 2, 3, 4 and 5 reps". `E1` is
        /// the second of ``loggedSets`` and `E4` the first working set of ``rampedSets``.
        static let personalRecords = SessionRecordMarks(
            bySetID: [
                identifier("E1"): [3],
                identifier("E4"): [1, 2, 3, 4, 5],
            ],
            hasLoaded: true
        )

        /// A session note as the field holds one that has been stored.
        static var storedNote: SessionNoteDraft {
            var draft = SessionNoteDraft()
            draft.follow(session.withNote("Bar felt fast. Next time start the ramp at 60."))
            return draft
        }

        /// The same note, edited and not yet saved — which is what puts the two commands on screen.
        static var editedNote: SessionNoteDraft {
            var draft = storedNote
            draft.text += " Sleeves from the second set."
            return draft
        }

        /// One logged set, with every identifier and timestamp fixed.
        private static func loggedSet(
            index: Int,
            weight: Weight,
            reps: Int,
            rpe: Double?,
            isWarmup: Bool = false,
            isCompleted: Bool = true,
            modifiers: [SetModifier] = []
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
                isWarmup: isWarmup,
                isCompleted: isCompleted,
                targetWeight: nil,
                targetReps: nil,
                modifiers: modifiers,
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

        /// Four exercises in one workout, at every shape a card has: finished and folded, part-done
        /// with a **folded** warmup group above the work, mid-ramp with that group still **open**,
        /// and unstarted with nothing in it. Every identifier and timestamp is fixed so a rendering
        /// never moves.
        ///
        /// The part-done card's working set is **failed** (`FR-1.2.5`), which is what leaves it
        /// part-done: an exercise is finished when every working set on it is completed, so an
        /// unfinished card in a fixture is a card carrying an uncompleted set by construction.
        ///
        /// The two warmup shapes are both here on purpose: `FR-1.2.14`'s group folds itself once
        /// the work starts, so which of the two a card shows is a fact about the card rather than a
        /// preference, and a fixture carrying only one of them would picture half the rule.
        static let exercises: [SessionExercise] = [
            sessionExercise(
                index: 1,
                name: "Back Squat",
                sets: [(isWarmup: false, isCompleted: true), (isWarmup: false, isCompleted: true)]
            ),
            sessionExercise(
                index: 2,
                name: "Bench Press",
                sets: [
                    (isWarmup: true, isCompleted: true), (isWarmup: true, isCompleted: true),
                    (isWarmup: false, isCompleted: false),
                ]
            ),
            sessionExercise(
                index: 4,
                name: "Overhead Press",
                sets: [(isWarmup: true, isCompleted: true), (isWarmup: true, isCompleted: true)]
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

    extension WorkoutSession {
        /// The same workout carrying a different note — the one field these references move.
        fileprivate func withNote(_ note: String) -> WorkoutSession {
            WorkoutSession(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                date: date,
                startedAt: startedAt,
                endedAt: endedAt,
                notes: note,
                bodyweight: bodyweight,
                programRunID: programRunID,
                scheduledWorkoutID: scheduledWorkoutID
            )
        }
    }

#endif
