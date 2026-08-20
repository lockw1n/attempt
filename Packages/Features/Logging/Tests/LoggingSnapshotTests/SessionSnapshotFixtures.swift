#if os(iOS)

    import Foundation
    import PowerliftingCore
    import RepositoryInterface

    @testable import Logging

    // The workout every reference in `SessionSnapshotTests` renders. A file of its own so neither it
    // nor the suite beside it runs into `file_length` — the two grow for different reasons, a
    // reference being added and a fixture shape being added.

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

        /// A ramp: two warmups and then the work, which is `FR-1.2.14`'s own example.
        static let rampedSets: [SetEntry] = [
            loggedSet(index: 2, weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true),
            loggedSet(index: 3, weight: Weight(grams: 80_000), reps: 3, rpe: nil, isWarmup: true),
            loggedSet(index: 4, weight: Weight(grams: 102_500), reps: 5, rpe: 8),
            loggedSet(index: 5, weight: Weight(grams: 102_500), reps: 5, rpe: 8.5),
            loggedSet(index: 6, weight: Weight(grams: 102_500), reps: 5, rpe: nil),
        ]

        /// One logged set, with every identifier and timestamp fixed.
        private static func loggedSet(
            index: Int, weight: Weight, reps: Int, rpe: Double?, isWarmup: Bool = false
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

        /// Four exercises in one workout, at every shape a card has: finished and folded, part-done
        /// with a **folded** warmup group above the work, mid-ramp with that group still **open**,
        /// and unstarted with nothing in it. Every identifier and timestamp is fixed so a rendering
        /// never moves.
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

#endif
