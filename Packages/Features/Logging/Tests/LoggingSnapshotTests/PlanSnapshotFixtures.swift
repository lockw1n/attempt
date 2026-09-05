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
        /// `FR-15.3.1` and `FR-15.3.2`'s cards: the plan drawn beside what was done, and the
        /// deviation where the two parted company.
        ///
        /// **Two cards here and two in ``completion``, rather than four in one reference, and the
        /// split is `ImageRenderer`'s ceiling rather than taste.** All four together render 8,494
        /// pixels tall at `accessibility3`, past the height where the renderer hands back a blank
        /// image — and the harness compares dimensions before pixels, so a blank recorded once
        /// matches a blank render forever and nothing fails. Narrowing the fixture was the other
        /// way out and would have cost a claim: each of these four cards is the only picture of
        /// something the requirement asks for. Split, each reference still proves what it was
        /// built to prove and both stay well under the height.
        ///
        /// The squat is the deviation case — one set that matched the top set exactly, one short of
        /// the backoff's reps and one over its load — and it is the card still carrying a
        /// **Planned next** section with its one-tap command, since its plan is not yet exhausted.
        /// The bench is `FR-15.2.2`'s blank target, whose line has to say the load was the lifter's
        /// and still measure the reps, and whose planned section therefore offers no one-tap
        /// command at all.
        ///
        /// **The short set on each card is what keeps it open**, and it is not a device: a card
        /// folds when every working set on it is completed, so an open card in a fixture is a card
        /// carrying an uncompleted set by construction — the same rule ``Fixtures/exercises`` is
        /// built on.
        static let deviations: [SessionExercise] = [
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
                ],
                // `FR-16.7.1` on both surfaces at once: 125 kg is the training max, so the target
                // line reads 80% and the set rows 80%, 68% and 70% — and the second card, which
                // has none, draws no share at all. That contrast is the reference's whole claim
                // about absence, and it is only visible with the two side by side.
                trainingMaxKilos: 125
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
        ]

        /// `FR-15.3.4`'s check-off in both of its meanings: an exercise finished early and one
        /// skipped outright, which are different words on the same flag.
        ///
        /// **These two fold for the reason the pair above stays open**, which is the half this
        /// reference adds: not that the work is complete, but that the lifter said so.
        static let completion: [SessionExercise] = [
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

        /// Which of ``completion``'s two cards the reference draws open.
        ///
        /// **The checked-off card is pinned open, and that is what that reference is for.** A card
        /// folds once it is done, so left to itself the fixture would picture
        /// ``ExerciseDoneToggle`` in one of its two states only — and the checked one is where
        /// `G-4.5` has something to prove: a filled glyph and a different word, neither of them
        /// tint. The skipped card is left folded, which is the other half of the same claim.
        static let expansion: [UUID: Bool] = [Fixtures.identifier("B7"): true]

        /// The group the set editor's target line is drawn from (`FR-15.3.1`, `FR-15.3.5`).
        ///
        /// ``deviations``' backoff, so the sheet's line reads as the one behind the squat card's
        /// second set — which is the set an adjustment is made on. **Taken from that card rather
        /// than rebuilt to match it**: written out a second time, the two agree until somebody
        /// edits the squat's plan, and the sentence above quietly stops being true.
        static var prescription: PlannedTargetGroup { deviations[0].planned[1] }

        /// One planned card: the exercise, what was prescribed for it and what was logged against
        /// it. Every identifier and timestamp is fixed so a rendering never moves.
        private static func card(
            index: Int,
            name: String,
            plan: [PlanGroupSpec],
            sets: [PlanSetSpec],
            isMarkedDone: Bool = false,
            trainingMaxKilos: Int? = nil
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
                },
                trainingMax: trainingMaxKilos.map { Weight(grams: $0 * 1000) }
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
