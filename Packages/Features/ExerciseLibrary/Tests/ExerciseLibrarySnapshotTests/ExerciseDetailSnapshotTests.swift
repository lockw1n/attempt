#if os(iOS)

    import DesignSystem
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import ExerciseLibrary

    // TR-1.12 for the detail screen, in the same four configurations as the list's references and on
    // the same terms — see `ExerciseListSnapshotTests` for why the pieces are rendered rather than the
    // screen, why a row's text is dimmer here than in the app, and why the copy is the real copy.
    //
    // FR-1.5.2's history is covered as a group rather than as a section, on the same terms: the
    // section's body is a `.task` that reads a store, and what a group of rows looks like is the
    // thing TR-1.12 is a gate over.
    //
    // THE NOTES SECTION HAS NO REFERENCE, and that is the harness's limit rather than an omission: it
    // is a `TextField`, `ImageRenderer` draws its unsupported-view placeholder for anything
    // UIKit-backed, and a reference over a grey rectangle would be a gate over nothing. What the notes
    // editor does is covered by `ExerciseDetailStateTests`; what it looks like is the simulator run's
    // (`docs/phase-1/tasks.md` §2).

    @MainActor
    @Suite("Exercise detail snapshots")
    struct ExerciseDetailSnapshotTests {
        @Test func facts() throws {
            try assertSnapshots(named: "ExerciseDetail-facts") {
                ExerciseFactsSection(exercise: DetailFixtures.frontSquat)
            }
        }

        @Test func archivedFacts() throws {
            try assertSnapshots(named: "ExerciseDetail-facts-archived") {
                ExerciseFactsSection(exercise: DetailFixtures.retired)
            }
        }

        @Test func variations() throws {
            try assertSnapshots(named: "ExerciseDetail-variations") {
                ExerciseVariationsSection(
                    parent: DetailFixtures.backSquat,
                    variations: [DetailFixtures.frontSquat, DetailFixtures.pauseSquat]
                )
            }
        }

        @Test func history() throws {
            // One picture with every row variant in it: a working set with a rating, one without,
            // a warmup, and a failed set. Four references over four rows rather than four suites —
            // what each of the four does to the row is a font, a colour and a word, and they are
            // only comparable side by side.
            try assertSnapshots(named: "ExerciseDetail-history") {
                ExerciseHistoryGroupView(group: DetailFixtures.trainingDay, unit: .kilograms)
            }
        }

        @Test func derivedValueWithNothingToShow() throws {
            try assertSnapshots(named: "ExerciseDetail-derived") {
                DerivedValueSection(
                    title: ExerciseLibraryStrings.e1rmSection,
                    nothingYet: ExerciseLibraryStrings.e1rmNone
                )
            }
        }

        @Test func archiveControl() throws {
            try assertSnapshots(named: "ExerciseDetail-archive") {
                ExerciseArchiveSection(isArchived: false, hasFailed: false) {}
            }
        }

        @Test func unarchiveControl() throws {
            // The archived direction *and* the failed write in one reference: they are the two
            // things this section renders that the live one does not, and a screen showing both is
            // the state a retry is offered from.
            try assertSnapshots(named: "ExerciseDetail-unarchive") {
                ExerciseArchiveSection(isArchived: true, hasFailed: true) {}
            }
        }

        @Test func exerciseNotFound() throws {
            try assertSnapshots(named: "ExerciseDetail-missing") {
                ErrorStateView(
                    headline: Text(ExerciseLibraryStrings.detailMissingHeadline),
                    message: Text(ExerciseLibraryStrings.detailMissingMessage)
                )
            }
        }
    }

    /// The exercises these references render: a parent, two variations, and an archived one.
    ///
    /// The variation carries a non-default bar and laterality so the reference shows the vocabulary
    /// mapping doing something rather than five rows of the schema's defaults.
    enum DetailFixtures {
        static let backSquat = Fixtures.exercise(id: 1, name: "Back Squat", movement: .squat)

        static let frontSquat = Fixtures.exercise(
            id: 2,
            name: "Front Squat",
            movement: .squat,
            isCustom: true,
            laterality: .unilateral,
            barType: .safetySquat
        )

        static let pauseSquat = Fixtures.exercise(id: 3, name: "Pause Squat", movement: .squat)

        static let retired = Fixtures.exercise(
            id: 4,
            name: "Retired Machine Press",
            movement: .bench,
            equipment: .machine,
            isArchived: true,
            barType: .noBar
        )

        /// One training day, carrying every distinction a history row draws (`FR-1.5.2`).
        ///
        /// The date is fixed rather than relative to now, so a reference committed today still
        /// matches next year. THE PAGE CONTROL HAS NO REFERENCE, and that is the same limit the
        /// notes section runs into one layer up: it lives inside `ExerciseHistorySection`, whose
        /// body is a `.task` that reads a store. What it does is `ExerciseHistoryStateTests`', and
        /// what it looks like is the simulator run's.
        static let trainingDay = ExerciseSessionHistory(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                loggedSet(order: 0, kilos: 60, reps: 5, isWarmup: true),
                loggedSet(order: 1, kilos: 102.5, reps: 5, rpe: 8),
                loggedSet(order: 2, kilos: 102.5, reps: 5),
                loggedSet(order: 3, kilos: 102.5, reps: 3, rpe: 9.5, isCompleted: false),
            ]
        )

        /// One set, spelled out once so a field nothing in the picture turns on is not repeated.
        private static func loggedSet(
            order: Int,
            kilos: Double,
            reps: Int,
            rpe: Double? = nil,
            isWarmup: Bool = false,
            isCompleted: Bool = true
        ) -> SetEntry {
            let stamp = Date(timeIntervalSince1970: 1_700_000_000)
            return SetEntry(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                entryID: UUID(),
                order: order,
                weight: Weight(grams: Int(kilos * 1000)),
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
