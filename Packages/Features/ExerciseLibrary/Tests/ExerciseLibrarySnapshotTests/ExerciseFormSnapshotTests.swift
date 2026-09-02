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

        // The same section over a BUILT-IN, and not a redundant reference: the Ukrainian name's
        // caption branches on `catalogueOwnsFields`, and this is the branch that says the catalogue
        // supplies the second name rather than the English one falling through (`FR-1.14.2`). The
        // other branch is what `ExerciseForm-fields` above photographs, `.create` always authoring a
        // custom row. The chip rows are replaced by the five catalogue-owned facts here, so this is
        // also the accessibility3 layout with the most copy stacked in it.
        @Test func fieldsSectionOnABuiltIn() async throws {
            let state = ExerciseFormState(
                mode: .edit(exerciseID: DetailFixtures.backSquat.id),
                repository: SilentExerciseRepository(stored: [DetailFixtures.backSquat]))
            await state.load()
            #expect(state.catalogueOwnsFields, "the fixture is not a built-in")

            try assertSnapshots(named: "ExerciseForm-fields-built-in") {
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

    /// An `ExerciseRepository` that answers from a fixed catalogue and is asked nothing else.
    ///
    /// The fields section reads the state's own properties, so for a `.create` reference the empty
    /// default is the whole collaborator. A `.edit` reference needs one thing more — `load()` reads
    /// its record back, and `catalogueOwnsFields` is false until it has — which is what ``stored``
    /// supplies. `RepositoryFakes`' in-memory stack would be the alternative and would be a
    /// dependency edge bought for the two answers below.
    private struct SilentExerciseRepository: ExerciseRepository {
        /// The catalogue `load()` reads from. Empty for a form that creates.
        var stored: [Exercise] = []

        func exercises(includingDeleted: Bool) async throws -> [Exercise] { stored }

        func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
            stored.first { $0.id == id }
        }

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
