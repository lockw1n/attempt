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

        @Test func derivedValueWithNothingToShow() throws {
            try assertSnapshots(named: "ExerciseDetail-derived") {
                DerivedValueSection(
                    title: ExerciseLibraryStrings.e1rmSection,
                    nothingYet: ExerciseLibraryStrings.e1rmNone
                )
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
    }

#endif
