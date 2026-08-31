#if os(iOS)

    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import ExerciseLibrary

    // TR-1.12 for the create/edit form, in the same four configurations as this module's other
    // references and on the same terms — see `ExerciseListSnapshotTests` for why the pieces are
    // rendered rather than the screen.
    //
    // TWO OF THIS SCREEN'S CONTROLS CANNOT BE PHOTOGRAPHED, and the second one was measured here.
    // The name field is a `TextField`, which `ImageRenderer` draws as its unsupported-view placeholder
    // — the detail screen's notes editor has the same limit. And a HORIZONTAL `ScrollView` RENDERS
    // EMPTY: an `ExerciseForm-options` reference over `OptionChipRow` came back with the row's label
    // drawn, the space below it the right height, and not one chip in it. That is the harness rather
    // than the row, and it reaches `ExerciseFilterBar` on the list screen identically. The chips
    // themselves are already a reference — `ExerciseList-filter-chips` renders one selected, one not
    // and one disabled — so nothing is lost but a duplicate; what the four rows look like in place is
    // the simulator run's (`docs/phase-1/tasks.md` §2).
    //
    // What the form *decides* is `ExerciseFormStateTests`' and `ExerciseFormParentTests`'; the parent
    // picker below is the part of it a reference can see, and selection is the one thing on this
    // screen a user reads back.
    //
    // `ExerciseForm-fields` is the fields section whole, and it is here for the field `FR-1.14.2`
    // added: the two text boxes come back as the placeholder above and the chip rows come back empty,
    // so what it actually pins is the LABELS AND THE TWO CAPTIONS — a required-name sentence and an
    // optional-Ukrainian-name one, stacked. That is the layout at risk at accessibility3 and the
    // half of this screen a reference can still see.
    //
    // The third reference is the form a BUILT-IN exercise gets, whose five catalogue-owned fields
    // are facts rather than controls (`FR-1.1.4`). It photographs where the chip rows do not, and it
    // is the layout most at risk at accessibility3: a paragraph of copy above five `ViewThatFits`
    // rows that stack when the two halves stop sharing a line.

    @MainActor
    @Suite("Exercise form snapshots")
    struct ExerciseFormSnapshotTests {
        @Test func parentPicker() throws {
            try assertSnapshots(named: "ExerciseForm-parent") {
                VStack(alignment: .leading) {
                    ExerciseParentList(
                        candidates: [DetailFixtures.backSquat, DetailFixtures.pauseSquat],
                        selection: .constant(DetailFixtures.backSquat.id)
                    )
                }
            }
        }

        @Test func builtInFieldsAreFacts() throws {
            try assertSnapshots(named: "ExerciseForm-catalogue-owned") {
                VStack(alignment: .leading) {
                    CatalogueOwnedFacts(
                        movement: .squat,
                        equipment: .barbell,
                        barType: .standard,
                        laterality: .bilateral,
                        parentName: "Back Squat"
                    )
                }
            }
        }

        @Test func fieldsSection() throws {
            let state = ExerciseFormState(mode: .create, repository: SilentExerciseRepository())
            try assertSnapshots(named: "ExerciseForm-fields") {
                VStack(alignment: .leading) {
                    ExerciseFieldsSection(state: state)
                }
            }
        }

        @Test func parentPickerWithNothingToOffer() throws {
            try assertSnapshots(named: "ExerciseForm-parent-empty") {
                VStack(alignment: .leading) {
                    ExerciseParentList(candidates: [], selection: .constant(nil))
                }
            }
        }
    }

    /// An `ExerciseRepository` that is never asked anything.
    ///
    /// The fields section reads the state's own properties and nothing else, and this reference does
    /// not call `load()` — so a repository is a constructor requirement here rather than a
    /// collaborator, and the empty answers say so. `RepositoryFakes`' in-memory stack would be the
    /// alternative and would be a dependency edge bought for a value nothing reads.
    private struct SilentExerciseRepository: ExerciseRepository {
        func exercises(includingDeleted: Bool) async throws -> [Exercise] { [] }

        func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? { nil }

        func save(_ exercise: Exercise) async throws {}

        func trainingMax(
            forExerciseID exerciseID: UUID,
            on date: Date
        ) async throws -> TrainingMaxEntry? { nil }

        func trainingMaxHistory(
            forExerciseID exerciseID: UUID,
            includingDeleted: Bool
        ) async throws -> [TrainingMaxEntry] { [] }

        func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {}
    }

#endif
