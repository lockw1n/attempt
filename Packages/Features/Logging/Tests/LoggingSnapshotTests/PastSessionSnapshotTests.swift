#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for `history.session` (T-1.39), in four configurations each — light and dark (`G-7.1`),
    // default and `accessibility3` (`NFR-1.10`'s own ceiling).
    //
    // WHAT IS RENDERED AND WHAT IS NOT. The card and the two placeholders, not `PastSessionView`
    // itself: the screen owns a `.task` that reads a store and `ImageRenderer` has no way to run one.
    // What the card's reference is *for* is the one thing this screen draws that no other reference
    // covers — a `SetRow` with its two marking controls absent, which is a past session's row. The
    // note section is already pictured by `SessionNoteSnapshotTests`, this screen drawing exactly the
    // same component.
    //
    // These are a regression baseline; the colours and the controls are what the simulator run checks
    // (`docs/phase-1/tasks.md` §2).

    @MainActor
    @Suite("Past session snapshots")
    struct PastSessionSnapshotTests {
        // MARK: - One past exercise (FR-1.2.7, FR-1.2.14)

        @Test func exerciseCard() throws {
            // A working set, a failed one and a folded warmup group, which is every shape a row on
            // this screen has. Two things a picture settles that a test cannot: the badge and the
            // outcome are drawn exactly where the live card draws them despite being labels here
            // rather than buttons, so the two screens' rows still align; and the failed set is red
            // and crossed, `G-4.5`'s two cues surviving a surface that cannot change the outcome.
            try assertSnapshots(named: "Past-session-card") {
                fixedEnvironment {
                    PastSessionExerciseCard(
                        item: PastFixtures.exercise,
                        unit: .kilograms,
                        areWarmupsExpanded: false,
                        toggleWarmups: {},
                        edit: { _ in }
                    )
                }
            }
        }

        @Test func exerciseCardWithWarmupsShown() throws {
            // The same card with `FR-1.2.14`'s group open, which is the other half of the fold and
            // the only place a `W1` badge appears on this screen.
            try assertSnapshots(named: "Past-session-card-warmups") {
                fixedEnvironment {
                    PastSessionExerciseCard(
                        item: PastFixtures.exercise,
                        unit: .kilograms,
                        areWarmupsExpanded: true,
                        toggleWarmups: {},
                        edit: { _ in }
                    )
                }
            }
        }

        // MARK: - The screen's own states (FR-1.13.1)

        @Test func sessionNotFound() throws {
            // The identifier that resolves to nothing, and the picture is the argument: there is no
            // retry button in it, because reading again resolves to nothing again.
            try assertSnapshots(named: "Past-session-missing") {
                ErrorStateView(
                    headline: Text(LoggingStrings.pastSessionMissingHeadline),
                    message: Text(LoggingStrings.pastSessionMissingMessage)
                )
            }
        }

        @Test func sessionWithNothingLogged() throws {
            // A workout that was started and never logged into. No action: a past session is a
            // record, and there is nothing to add to it from here.
            try assertSnapshots(named: "Past-session-empty") {
                EmptyStateView(
                    symbolName: "figure.strengthtraining.traditional",
                    headline: Text(LoggingStrings.pastSessionEmptyHeadline),
                    message: Text(LoggingStrings.pastSessionEmptyMessage)
                )
            }
        }
    }

    /// The exercise these references render.
    ///
    /// A type of its own rather than an addition to `Fixtures`, which is already at the size its own
    /// file was split out for.
    enum PastFixtures {
        /// A fixed point in time, so nothing here depends on when the suite runs.
        static let stamp = Date(timeIntervalSince1970: 1_700_000_000)

        /// One exercise as it was performed: two warmups, two working sets, one of them failed.
        static var exercise: SessionExercise {
            let entryID = UUID()
            return SessionExercise(
                entry: ExerciseEntry(
                    id: entryID,
                    createdAt: stamp,
                    updatedAt: stamp,
                    deletedAt: nil,
                    sessionID: UUID(),
                    exerciseID: UUID(),
                    order: 0,
                    notes: ""
                ),
                exercise: catalogueRow,
                sets: [
                    set(entryID: entryID, order: 0, grams: 60_000, reps: 5, isWarmup: true),
                    set(entryID: entryID, order: 1, grams: 80_000, reps: 3, isWarmup: true),
                    set(entryID: entryID, order: 2, grams: 102_500, reps: 5, rpe: 8),
                    set(entryID: entryID, order: 3, grams: 102_500, reps: 3, isCompleted: false),
                ]
            )
        }

        /// The catalogue row the card names.
        static var catalogueRow: Exercise {
            Exercise(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                name: "Back Squat",
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
                manualE1RM: nil)
        }

        /// One logged set, with only what the references vary named.
        ///
        /// - Parameters:
        ///   - entryID: The exercise it belongs to.
        ///   - order: Its place among that exercise's sets.
        ///   - grams: The load.
        ///   - reps: The repetitions.
        ///   - rpe: The rating, where it carried one.
        ///   - isWarmup: Whether it is a warmup.
        ///   - isCompleted: Whether it was completed rather than failed.
        /// - Returns: The set.
        static func set(
            entryID: UUID,
            order: Int,
            grams: Int,
            reps: Int,
            rpe: Double? = nil,
            isWarmup: Bool = false,
            isCompleted: Bool = true
        ) -> SetEntry {
            SetEntry(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                entryID: entryID,
                order: order,
                weight: Weight(grams: grams),
                reps: reps,
                rpe: rpe,
                rir: nil,
                isWarmup: isWarmup,
                isCompleted: isCompleted,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: nil
            )
        }
    }

#endif
