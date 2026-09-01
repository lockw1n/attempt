#if os(iOS)

    import Foundation
    import PowerliftingCore
    import RepositoryInterface

    @testable import Logging

    // `FR-15.3`'s cards, in a file of their own for `SessionSnapshotFixtures.swift`'s reason: that
    // one had reached `file_length` and `type_body_length` together, and a fixture shape being added
    // is exactly the growth those two are drawn around.

    /// One prescribed group, as this file's cards name one.
    ///
    /// A value rather than a tuple: three members is one past `large_tuple`'s ceiling, and the
    /// labels are what make a call site readable at four cards' worth of them.
    struct PlanGroupSpec {
        /// The prescribed load, or `nil` for `FR-15.2.2`'s blank target.
        let grams: Int?

        /// Reps prescribed per set.
        let reps: Int

        /// Sets prescribed.
        let sets: Int
    }

    /// One logged set, likewise.
    struct PlanSetSpec {
        /// What was lifted.
        let grams: Int

        /// How many times.
        let reps: Int

        /// Whether it was completed (`FR-1.2.5`) — what decides whether its card is folded.
        let isCompleted: Bool
    }

    /// The workout `SessionPlanSnapshotTests` renders.
    enum PlanFixtures {
        /// `FR-15.3`'s cards: the plan drawn beside what was done, at every shape the pair has.
        ///
        /// **Four cards, because the requirement has four answers and a fixture with one would
        /// picture none of the others.** The squat is the deviation case — one set that matched the
        /// top set exactly, one short of the backoff's reps and one over its load — and it is the
        /// card still carrying a **Planned next** section with its one-tap command, since its plan
        /// is not yet exhausted. The bench is `FR-15.2.2`'s blank target, whose line has to say the
        /// load was the lifter's and still measure the reps, and whose planned section therefore
        /// offers no one-tap command at all. The last two are `FR-15.3.4`'s check-off in both of
        /// its meanings: an exercise finished early and one skipped outright, which are different
        /// words on the same flag.
        ///
        /// **The short set on each of the first two cards is what keeps them open**, and it is not
        /// a device: a card folds when every working set on it is completed, so an open card in a
        /// fixture is a card carrying an uncompleted set by construction — the same rule
        /// ``Fixtures/exercises`` is built on. The last two fold for the other reason, which is the
        /// half this fixture adds: the lifter said so.
        static let exercises: [SessionExercise] = [
            card(
                index: 5,
                name: "Back Squat",
                plan: [
                    PlanGroupSpec(grams: 100_000, reps: 5, sets: 1),
                    PlanGroupSpec(grams: 85_000, reps: 8, sets: 3),
                ],
                sets: [
                    PlanSetSpec(grams: 100_000, reps: 5, isCompleted: true),
                    PlanSetSpec(grams: 85_000, reps: 7, isCompleted: false),
                    PlanSetSpec(grams: 87_500, reps: 8, isCompleted: true),
                ]
            ),
            card(
                index: 6,
                name: "Bench Press",
                plan: [PlanGroupSpec(grams: nil, reps: 5, sets: 3)],
                sets: [
                    PlanSetSpec(grams: 60_000, reps: 5, isCompleted: true),
                    PlanSetSpec(grams: 62_500, reps: 4, isCompleted: false),
                ]
            ),
            card(
                index: 7,
                name: "Overhead Press",
                plan: [PlanGroupSpec(grams: 40_000, reps: 8, sets: 3)],
                sets: [PlanSetSpec(grams: 40_000, reps: 8, isCompleted: true)],
                isMarkedDone: true
            ),
            card(
                index: 8,
                name: "Romanian Deadlift",
                plan: [PlanGroupSpec(grams: 90_000, reps: 8, sets: 3)],
                sets: [],
                isMarkedDone: true
            ),
        ]

        /// One planned card: the exercise, what was prescribed for it and what was logged against
        /// it. Every identifier and timestamp is fixed so a rendering never moves.
        private static func card(
            index: Int,
            name: String,
            plan: [PlanGroupSpec],
            sets: [PlanSetSpec],
            isMarkedDone: Bool = false
        ) -> SessionExercise {
            let entryID = Fixtures.identifier("B\(index)")
            let exerciseID = Fixtures.identifier("C\(index)")
            return SessionExercise(
                entry: ExerciseEntry(
                    id: entryID,
                    createdAt: Fixtures.startedAt,
                    updatedAt: Fixtures.startedAt,
                    deletedAt: nil,
                    sessionID: Fixtures.session.id,
                    exerciseID: exerciseID,
                    order: index - 1,
                    notes: "",
                    isMarkedDone: isMarkedDone
                ),
                exercise: exercise(id: exerciseID, named: name),
                sets: sets.enumerated().map { position, values in
                    Fixtures.loggedSet(
                        index: index * 10 + position,
                        weight: Weight(grams: values.grams),
                        reps: values.reps,
                        rpe: nil,
                        isCompleted: values.isCompleted
                    )
                },
                planned: plan.enumerated().map { position, group in
                    PlannedTargetGroup(
                        id: Fixtures.identifier("F\(index)\(position)"),
                        createdAt: Fixtures.startedAt,
                        updatedAt: Fixtures.startedAt,
                        deletedAt: nil,
                        exerciseEntryID: entryID,
                        order: position,
                        targetWeight: group.grams.map(Weight.init(grams:)),
                        targetReps: group.reps,
                        targetSets: group.sets
                    )
                }
            )
        }

        /// The catalogue row a card names.
        private static func exercise(id: UUID, named name: String) -> Exercise {
            Exercise(
                id: id,
                createdAt: Fixtures.startedAt,
                updatedAt: Fixtures.startedAt,
                deletedAt: nil,
                name: name,
                ukrainianName: nil,
                movement: .squat,
                parentExerciseID: nil,
                equipment: .barbell,
                laterality: .bilateral,
                barType: .standard,
                implementCount: 1,
                isCustom: false,
                isArchived: false,
                notes: "",
                manualE1RM: nil
            )
        }
    }

#endif
