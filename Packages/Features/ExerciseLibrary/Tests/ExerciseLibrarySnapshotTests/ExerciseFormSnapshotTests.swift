#if os(iOS)

    import PowerliftingCore
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

        @Test func parentPickerWithNothingToOffer() throws {
            try assertSnapshots(named: "ExerciseForm-parent-empty") {
                VStack(alignment: .leading) {
                    ExerciseParentList(candidates: [], selection: .constant(nil))
                }
            }
        }
    }

#endif
