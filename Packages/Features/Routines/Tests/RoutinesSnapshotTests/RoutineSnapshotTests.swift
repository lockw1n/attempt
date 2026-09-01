#if os(iOS)

    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Routines

    // TR-1.12 for this module's two screens, in the same four configurations as every other
    // module's references and on the same terms.
    //
    // WHAT A REFERENCE CANNOT SEE HERE, and it is most of the editor: every field on a target group
    // is a `TextField`, which `ImageRenderer` draws as its unsupported-view placeholder — the same
    // limit `ExerciseFormSnapshotTests` records for the name field. So the editor's references pin
    // the LABELS, the group headings, the reorder commands and FR-15.2.2's blank-target caption,
    // which is the half of this screen a reference can still check and the half most at risk at
    // accessibility3: three 44pt controls beside a heading, in a `ViewThatFits`.
    //
    // What the editor DECIDES is `RoutineEditorStateTests`', and what it does in place is the
    // simulator run's (`docs/phase-1/tasks.md` §2).

    @MainActor
    @Suite("Routine snapshots")
    struct RoutineSnapshotTests {
        @Test func listRows() throws {
            try assertSnapshots(named: "RoutineList-rows") {
                VStack(alignment: .leading) {
                    RoutineRow(
                        routine: RoutineSummary(
                            id: UUID(), name: "Heavy squat day", exerciseCount: 4))
                    RoutineRow(
                        routine: RoutineSummary(id: UUID(), name: "Press", exerciseCount: 1))
                }
            }
        }

        // The row a store this app did not write can still produce: the editor refuses an empty
        // name, so this is the stand-in rather than a state the app can author.
        @Test func listRowWithNoName() throws {
            try assertSnapshots(named: "RoutineList-unnamed") {
                VStack(alignment: .leading) {
                    RoutineRow(routine: RoutineSummary(id: UUID(), name: "  ", exerciseCount: 0))
                }
            }
        }

        // A slot with two groups — FR-15.2.1's amendment, a top set and a backoff — and the second
        // of them blank, which is FR-15.2.2's caption in the one place a reference can read it.
        @Test func slotCardWithTwoTargets() async throws {
            let store = try await populatedEditor()
            try assertSnapshots(named: "RoutineEditor-slot") {
                VStack(alignment: .leading) {
                    RoutineSlotCard(store: store, slot: store.slots[0], index: 0)
                }
            }
        }

        @Test func emptyExerciseList() async throws {
            let store = try await emptyEditor()
            try assertSnapshots(named: "RoutineEditor-no-exercises") {
                VStack(alignment: .leading) {
                    RoutineSlotsSection(store: store)
                }
            }
        }

        @Test func nameSectionAsksForAName() async throws {
            let store = try await emptyEditor()
            try assertSnapshots(named: "RoutineEditor-name") {
                VStack(alignment: .leading) {
                    RoutineNameSection(store: store)
                }
            }
        }

        /// An editor that has been read and holds nothing.
        private func emptyEditor() async throws -> RoutineEditorState {
            let store = RoutineEditorState(
                repository: SilentRoutineRepository(),
                catalogue: SilentExerciseRepository(),
                settings: SilentSettingsRepository())
            store.locale = Locale(identifier: "en_US_POSIX")
            await store.open(.create)
            return store
        }

        /// An editor holding one exercise with a filled top set and a blank backoff.
        private func populatedEditor() async throws -> RoutineEditorState {
            let store = try await emptyEditor()
            await store.addExercise(id: SilentExerciseRepository.squat.id)
            store.updateGroup(at: 0, inSlotAt: 0) { group in
                group.weightText = "180"
                group.repsText = "3"
                group.setsText = "1"
            }
            store.addGroup(toSlotAt: 0)
            store.updateGroup(at: 1, inSlotAt: 0) { group in
                group.repsText = "8"
                group.setsText = "3"
            }
            return store
        }
    }

    /// A catalogue holding one exercise and asked nothing else.
    ///
    /// A hand-written double rather than `RepositoryFakes`, which is the shape
    /// `ExerciseFormSnapshotTests` uses: the reference needs two answers, and a dependency edge
    /// bought for two answers is a dependency edge.
    private struct SilentExerciseRepository: ExerciseRepository {
        /// The one row a slot in these references names.
        static let squat = Exercise(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
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

        func exercises(includingDeleted: Bool) async throws -> [Exercise] { [Self.squat] }

        func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
            id == Self.squat.id ? Self.squat : nil
        }

        func save(_ exercise: Exercise) async throws {}

        func trainingMax(
            forExerciseID exerciseID: UUID, on date: Date
        ) async throws -> TrainingMaxEntry? { nil }

        func trainingMaxHistory(
            forExerciseID exerciseID: UUID, includingDeleted: Bool
        ) async throws -> [TrainingMaxEntry] { [] }

        func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {}
    }

    /// A settings row in kilograms, which is the unit these references are drawn in.
    private struct SilentSettingsRepository: SettingsRepository {
        func settings() async throws -> UserSettings {
            UserSettings(
                id: UUID(),
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                userID: UUID(),
                displayUnit: .kilograms,
                e1RMFormula: .epley,
                theme: .dark,
                defaultRoundingIncrement: Weight(grams: 2500),
                defaultRoundingStrategy: .nearest)
        }

        func save(_ settings: UserSettings) async throws {}
    }

    /// A routine store nothing in these references reads or writes — the editor opens on
    /// `.create`, which reads no routine at all.
    private struct SilentRoutineRepository: RoutineRepository {
        func routines(includingDeleted: Bool) async throws -> [Routine] { [] }

        func routine(id: UUID, includingDeleted: Bool) async throws -> Routine? { nil }

        func save(_ routine: Routine) async throws {}

        func deleteRoutine(id: UUID) async throws {}

        func exercises(
            forRoutineID routineID: UUID, includingDeleted: Bool
        ) async throws -> [RoutineExercise] { [] }

        func routineExercise(id: UUID, includingDeleted: Bool) async throws -> RoutineExercise? {
            nil
        }

        func save(_ exercise: RoutineExercise) async throws {}

        func deleteRoutineExercise(id: UUID) async throws {}

        func targetGroups(
            forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
        ) async throws -> [RoutineTargetGroup] { [] }

        func save(_ group: RoutineTargetGroup) async throws {}

        func deleteTargetGroup(id: UUID) async throws {}
    }

#endif
