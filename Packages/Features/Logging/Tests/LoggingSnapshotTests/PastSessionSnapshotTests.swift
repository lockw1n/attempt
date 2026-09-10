#if os(iOS)

    import DesignSystem
    import DesignTokens
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
    // WHAT IS RENDERED AND WHAT IS NOT. The pieces, not `PastSessionView` itself: the screen owns a
    // `.task` that reads a store and `ImageRenderer` has no way to run one.
    //
    // TWO SHAPES, AND BOTH ARE PICTURED (`FR-17.7.6`). A past *free workout* is the card, whose
    // reference is for the one thing no other covers — a `SetRow` with its two marking controls
    // absent. A past *planned day* is `DayChecklistSection`, which the Train tab also draws: what
    // its references here are for is the difference, which is what is MISSING — no circle on an
    // unanswered row and no **Skip** in the menu, because those are how a day is answered and this
    // one has been.
    //
    // THE NOTE IS THE FOLD NOW (`FR-17.7.1`), pictured here at `.primary` where
    // `SessionAboveFoldSnapshotTests` pictures it at `.secondary` — that emphasis is the whole
    // difference between the two screens' copies of one component, and it is the half a test cannot
    // hold (T-16.17).
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
                        expandedGroups: [],
                        toggleGroup: { _ in },
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
                        expandedGroups: [],
                        toggleGroup: { _ in },
                        edit: { _ in }
                    )
                }
            }
        }

        @Test func exerciseCardWithGroups() throws {
            // `FR-16.1.1` on the past session: four identical sets as one line, and the set that
            // broke the run as a row beneath it. Its own reference rather than a variant of the
            // card above, because that fixture has no run in it at all — which is the state this
            // screen was in before the grouping and is worth keeping a picture of.
            try assertSnapshots(named: "Past-session-card-groups") {
                fixedEnvironment {
                    PastSessionExerciseCard(
                        item: PastFixtures.groupedExercise,
                        unit: .kilograms,
                        areWarmupsExpanded: false,
                        toggleWarmups: {},
                        expandedGroups: [],
                        toggleGroup: { _ in },
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

        @Test func exerciseCardWithRecordAndNotes() throws {
            // `FR-17.7.2` and `FR-17.7.4` on one card, because they land in the same two places and
            // the question each raises is the other's. The badge is the cache's answer — this run
            // holds the record NOW — and the note is drawn on the collapsed line with the member
            // rows quiet, which is where `SetGrouping.Grain.displayed` puts it: that grain compares
            // the note, so every member of a run carries the same one and the line above them says
            // it once (T-16.13's three answers).
            //
            // The single set below the run is the other half: a group of one has no line above it,
            // so it states its own.
            try assertSnapshots(named: "Past-session-record") {
                fixedEnvironment {
                    PastSessionExerciseCard(
                        item: PastFixtures.notedExercise,
                        unit: .kilograms,
                        areWarmupsExpanded: false,
                        toggleWarmups: {},
                        expandedGroups: [],
                        toggleGroup: { _ in },
                        edit: { _ in },
                        recordMarks: { PastFixtures.recordSchemes[$0] ?? [] }
                    )
                }
            }
        }

        @Test func exerciseCardWithTheRunOpen() throws {
            // The same card with the run expanded, which is the reference the rule above needs:
            // the members are drawn and none of them repeats the note the line already carries.
            try assertSnapshots(named: "Past-session-set-note") {
                fixedEnvironment {
                    PastSessionExerciseCard(
                        item: PastFixtures.notedExercise,
                        unit: .kilograms,
                        areWarmupsExpanded: false,
                        toggleWarmups: {},
                        expandedGroups: PastFixtures.notedGroupIDs,
                        toggleGroup: { _ in },
                        edit: { _ in },
                        recordMarks: { PastFixtures.recordSchemes[$0] ?? [] }
                    )
                }
            }
        }

        // MARK: - FR-1.2.9's note, folded at the foot (FR-17.7.1)
        //
        // ONE REFERENCE, NOT TWO, AND `shasum` IS WHY. A `Past-session-notes` picturing the CLOSED
        // fold was recorded here and came back byte-identical to `Session-notes` in all four
        // configurations: `saveEmphasis` reaches only the button inside the fold, so closed, the two
        // screens' copies of this component are one picture. A second reference for one claim is
        // what a hash across the whole directory catches and no other gate does, so it went.

        @Test func notesFoldUnsavedAndFailed() throws {
            // Open, over an edit that has not been stored and a write that failed. This is where
            // `.primary` is legible: **Save note** is filled here and outlined on the active
            // session, and it is this screen's one filled command (`FR-16.6.4`).
            try assertSnapshots(named: "Past-session-notes-editing") {
                fixedEnvironment {
                    SessionNotesFold(
                        draft: .constant(Fixtures.editedNote),
                        isExpanded: .constant(true),
                        hasFailed: true,
                        saveEmphasis: .primary,
                        save: {})
                }
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

        /// The same exercise performed as a run: a warmup, then four identical working sets and a
        /// fifth a rep short (`FR-16.1.1`).
        static var groupedExercise: SessionExercise {
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
                    set(entryID: entryID, order: 1, grams: 100_000, reps: 6, rpe: 8),
                    set(entryID: entryID, order: 2, grams: 100_000, reps: 6, rpe: 8),
                    set(entryID: entryID, order: 3, grams: 100_000, reps: 6, rpe: 8),
                    set(entryID: entryID, order: 4, grams: 100_000, reps: 6, rpe: 8),
                    set(entryID: entryID, order: 5, grams: 100_000, reps: 5, rpe: 9),
                ]
            )
        }

        /// The note four members of the run share, and the one the fifth set carries alone.
        static let beltNote = "Belt on from the third"

        /// See ``beltNote``.
        static let kneeNote = "Left knee felt off"

        /// ``notedExercise``'s sets, built **once**.
        ///
        /// **A `let` rather than a computed property, and that is the fixture's correctness rather
        /// than its cost.** The badge is keyed on a set's identifier and the fold on a group's, so a
        /// property that minted fresh `UUID`s per call would hand the card one set of ids and the
        /// two maps beside it another — a reference picturing no badge and no open group, and
        /// nothing in the harness able to say why.
        static let notedSetList = notedSets(entryID: UUID())

        /// A run of four carrying one note and holding a record, then a single set with a note of
        /// its own — the two placements `FR-17.7.4` has to settle.
        static var notedExercise: SessionExercise {
            SessionExercise(
                entry: entry(id: notedSetList[0].entryID),
                exercise: catalogueRow,
                sets: notedSetList
            )
        }

        /// Which of ``notedExercise``'s sets hold a record, keyed on the set.
        ///
        /// **The run's FIRST set**, which is the identifier the cache names a run by
        /// (`PersonalRecordCacheEntity.sourceSetID`) — a badge keyed on any other member would draw
        /// nothing, and a fixture that keyed it on all four would picture a rule the store does not
        /// implement.
        static var recordSchemes: [UUID: [SchemeMark]] {
            [
                notedSetList[0].id: [
                    SchemeMark(scheme: RecordScheme(reps: 6, sets: 4), isFirstPerformance: false)
                ]
            ]
        }

        /// Every group on ``notedExercise``'s card, so a reference can draw them all open.
        static var notedGroupIDs: Set<UUID> {
            Set(SetNumbering.grouped(SetNumbering.numbered(notedSetList)).map(\.id))
        }

        /// One entry, with only its identifier named.
        ///
        /// - Parameter id: The entry.
        /// - Returns: The record.
        static func entry(id: UUID) -> ExerciseEntry {
            ExerciseEntry(
                id: id,
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: UUID(),
                exerciseID: UUID(),
                order: 0,
                notes: ""
            )
        }

        /// ``notedExercise``'s sets: a run of four sharing a note, then one set with another.
        ///
        /// - Parameter entryID: The exercise they belong to.
        /// - Returns: The sets, in order.
        static func notedSets(entryID: UUID) -> [SetEntry] {
            (0..<4).map {
                set(entryID: entryID, order: $0, grams: 100_000, reps: 6, notes: beltNote)
            } + [set(entryID: entryID, order: 4, grams: 90_000, reps: 8, notes: kneeNote)]
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
                notes: "")
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
        ///   - notes: `FR-1.2.3`'s per-set note, where it carried one.
        /// - Returns: The set.
        static func set(
            entryID: UUID,
            order: Int,
            grams: Int,
            reps: Int,
            rpe: Double? = nil,
            isWarmup: Bool = false,
            isCompleted: Bool = true,
            notes: String = ""
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
                notes: notes,
                completedAt: nil
            )
        }
    }

#endif
