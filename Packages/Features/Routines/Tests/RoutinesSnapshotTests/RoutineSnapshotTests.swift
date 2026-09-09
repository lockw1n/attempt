#if os(iOS)

    import DesignSystem
    import DesignTokens
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Routines

    // TR-1.12 for FR-17.10's one screen, in the same four configurations as every other module's
    // references and on the same terms.
    //
    // EVERY FIXTURE HERE IS THE SCREEN'S OWN VIEW OVER THE SCREEN'S OWN STORE, which is T-16.17's
    // rule taken at its word: a fixture that assembled `EmptyStateView` or a day's header by hand
    // would be a second place the screen's decisions live, and the four references it found wrong
    // were all of that shape. The store is read through the doubles below rather than populated by
    // hand, so what is drawn is what `WeekEditorState.load()` produces.
    //
    // WHAT A REFERENCE CANNOT SEE HERE, and it is more than T-17.08's file predicted. Every field
    // on a target group is a `TextField` and every command menu is a `Menu`; `ImageRenderer` draws
    // BOTH as its unsupported-view placeholder — T-17.08 recorded that a menu's presented items are
    // not renderable and its button is, and the button is not either. What the placeholders still
    // pin is their FRAME, which is the half that matters for `G-4.3`: a menu that stopped being
    // 44 pt, or a field that stopped reserving a line, moves the picture.
    //
    // WHICH LAYOUT A REFERENCE SHOWS, and this paragraph is a correction — it once described the
    // FIRST version of `RoutineGroupRow`, which picked between the inline `[105] kg × [4] × [4]`
    // and the labelled stack with `ViewThatFits`, lost to the placeholder's width at every size,
    // and was replaced before this commit landed. What ships reads `dynamicTypeSize` directly, so
    // the split here is clean: the `.default` references ARE `FR-17.10.1`'s notation and the
    // `.accessibility3` ones ARE the labelled stack, each drawn by the branch the app takes at that
    // size. What the placeholders cost is the field CONTENTS, not the arrangement — the numbers a
    // reader would see in the boxes are `WeekEditorStateTests`', and so are the menu items.
    //
    // So what these pin is the day header and its fold, the three stand-ins a day's name can take,
    // the empty state and its one command, the target headings, and FR-15.2.2's blank-target
    // caption.
    //
    // NEVER THE SCREEN ITSELF: `WeekEditorView` wraps a `ScrollView`, which records as its
    // UIKit-backed placeholder (T-16.06). These render the sections inside it.

    @MainActor
    @Suite("Week editor snapshots")
    struct WeekEditorSnapshotTests {
        /// `FR-1.13.2`'s first launch, reached from **Plan your week** — the state a fresh install
        /// opens this screen in, with the only command it carries.
        @Test func emptyWeek() async throws {
            let store = try await editor(over: WeekFixture(days: []))
            try assertSnapshots(named: "WeekEditor-empty") {
                VStack(alignment: .leading) {
                    WeekDaysSection(store: store, rename: { _ in }, remove: { _ in })
                }
            }
        }

        /// Three days folded, which is what a lifter reads the week as: the position, the name and
        /// the menu, with `FR-15.2.5`'s archived day among them so the nameless case is drawn.
        @Test func daysFolded() async throws {
            let store = try await editor(over: WeekFixture.week)
            try assertSnapshots(named: "WeekEditor-days") {
                VStack(alignment: .leading) {
                    WeekDaysSection(store: store, rename: { _ in }, remove: { _ in })
                }
            }
        }

        /// One day open: its exercises, their targets, and the command that adds another. The one
        /// configuration the fold exists for — `accessibility3` is where a week with every day
        /// open stops fitting a render at all.
        @Test func openDay() async throws {
            let store = try await editor(over: WeekFixture.week)
            store.openDayID = store.days.first?.id
            try assertSnapshots(named: "WeekEditor-day-open") {
                VStack(alignment: .leading) {
                    WeekEditorDaySection(
                        store: store,
                        day: store.days[0],
                        index: 0,
                        rename: {},
                        remove: {})
                }
            }
        }

        /// `FR-17.10.1`'s set notation and the size at which it stops being one: a filled top set
        /// and a blank backoff, which is `FR-15.2.2`'s caption in the one place a reference can
        /// read it.
        @Test func targetRows() async throws {
            let store = try await editor(over: WeekFixture.week)
            try assertSnapshots(named: "WeekEditor-target-row") {
                VStack(alignment: .leading) {
                    RoutineGroupRow(
                        store: store,
                        group: store.days[0].slots[0].groups[0],
                        groupIndex: 0,
                        slotIndex: 0,
                        dayIndex: 0)
                    RoutineGroupRow(
                        store: store,
                        group: store.days[0].slots[0].groups[1],
                        groupIndex: 1,
                        slotIndex: 0,
                        dayIndex: 0)
                }
            }
        }

        /// An editor that has read `fixture`.
        private func editor(over fixture: WeekFixture) async throws -> WeekEditorState {
            let store = WeekEditorState(
                programs: fixture,
                routines: fixture,
                catalogue: fixture,
                settings: fixture)
            store.locale = Locale(identifier: "en_US_POSIX")
            await store.open(screen: UUID())
            return store
        }
    }

    /// The week these references are drawn over, as the four repositories the editor reads.
    ///
    /// **One double for all four**, which is `SilentExerciseRepository`'s shape at the size this
    /// screen needs: the editor joins six tables, and four hand-written types would be four places
    /// to keep one week consistent.
    private struct WeekFixture {
        /// One day of the fixture: what it is called, and what it prescribes.
        struct Day {
            /// The routine's name, or `nil` for a day whose routine has been archived.
            let name: String?

            /// The exercises it trains, in order.
            let slots: [Slot]
        }

        /// One exercise of a fixture day.
        struct Slot {
            /// The catalogue name drawn on the card.
            let name: String

            /// What the day prescribes for it, in order.
            let groups: [Target]
        }

        /// One target group of a fixture exercise.
        struct Target {
            /// The load in grams, or `nil` for `FR-15.2.2`'s blank target.
            let grams: Int?

            /// Reps prescribed per set.
            let reps: Int

            /// Sets prescribed.
            let sets: Int
        }

        /// The days, in order.
        let days: [Day]

        /// A week a lifter would recognise: a heavy day with a top set and a blank backoff, a
        /// second day, and a third whose routine has been archived.
        static let week = WeekFixture(days: [
            Day(
                name: "Heavy squat day",
                slots: [
                    Slot(
                        name: "Back Squat",
                        groups: [
                            Target(grams: 180_000, reps: 3, sets: 1),
                            Target(grams: nil, reps: 8, sets: 3),
                        ]),
                    Slot(
                        name: "Romanian Deadlift",
                        groups: [Target(grams: 100_000, reps: 8, sets: 3)]),
                ]),
            Day(
                name: "Bench and accessories",
                slots: [
                    Slot(name: "Bench Press", groups: [Target(grams: 105_000, reps: 4, sets: 4)])
                ]),
            Day(name: nil, slots: []),
        ])

        /// The program row every day hangs off.
        private static let programID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()

        /// The identifier of the day at `index`, stable so a re-read draws the same week.
        private func dayID(_ index: Int) -> UUID { deterministic(1, index, 0) }

        /// The identifier of the routine behind the day at `index`.
        private func routineID(_ index: Int) -> UUID { deterministic(2, index, 0) }

        /// The identifier of the slot at `slot` in the day at `day`.
        private func slotID(_ day: Int, _ slot: Int) -> UUID { deterministic(3, day, slot) }

        /// A stable identifier from a table and two coordinates, so nothing here mints one per
        /// read — a fixture whose ids moved between reads would redraw as a different week.
        private func deterministic(_ table: Int, _ first: Int, _ second: Int) -> UUID {
            UUID(
                uuidString: "\(table)0000000-0000-4000-8000-"
                    + String(format: "%06d%06d", first, second)) ?? UUID()
        }

        /// Which day a routine identifier belongs to.
        private func dayIndex(ofRoutineID id: UUID) -> Int? {
            days.indices.first { routineID($0) == id }
        }

        /// Which slot a slot identifier names.
        private func slotIndex(of id: UUID) -> (day: Int, slot: Int)? {
            for day in days.indices {
                for slot in days[day].slots.indices where slotID(day, slot) == id {
                    return (day, slot)
                }
            }
            return nil
        }

    }

    extension WeekFixture: ProgramRepository {
        func programs(includingDeleted: Bool) async throws -> [Program] { [Self.program] }

        func program(id: UUID, includingDeleted: Bool) async throws -> Program? {
            id == Self.programID ? Self.program : nil
        }

        func save(_ program: Program) async throws {}

        func deleteProgram(id: UUID) async throws {}

        func days(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramDay] {
            days.indices.map { index in
                ProgramDay(
                    id: dayID(index),
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    deletedAt: nil,
                    programID: Self.programID,
                    routineID: routineID(index),
                    order: index)
            }
        }

        func programDay(id: UUID, includingDeleted: Bool) async throws -> ProgramDay? { nil }

        func save(_ day: ProgramDay) async throws {}

        func deleteDay(id: UUID) async throws {}

        func currentRun() async throws -> ProgramRun? {
            days.isEmpty ? nil : Self.run
        }

        func runs(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramRun] {
            [Self.run]
        }

        func run(id: UUID, includingDeleted: Bool) async throws -> ProgramRun? { Self.run }

        func startRun(_ run: ProgramRun) async throws {}

        func save(_ run: ProgramRun) async throws {}

        func deleteRun(id: UUID) async throws {}

        /// The program the week is.
        private static let program = Program(
            id: programID,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            name: "Squat block",
            notes: "")

        /// The run in force.
        private static let run = ProgramRun(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333") ?? UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            programID: programID,
            startedAt: .distantPast,
            endedAt: nil,
            weekNumber: 1,
            nextDayIndex: 0)

    }

    extension WeekFixture: RoutineRepository {
        func routines(includingDeleted: Bool) async throws -> [Routine] { [] }

        func routine(id: UUID, includingDeleted: Bool) async throws -> Routine? {
            guard let index = dayIndex(ofRoutineID: id), let name = days[index].name else {
                return nil
            }
            return Routine(
                id: id,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                name: name)
        }

        func save(_ routine: Routine) async throws {}

        func deleteRoutine(id: UUID) async throws {}

        func exercises(
            forRoutineID routineID: UUID, includingDeleted: Bool
        ) async throws -> [RoutineExercise] {
            guard let index = dayIndex(ofRoutineID: routineID) else { return [] }
            return days[index].slots.indices.map { slot in
                RoutineExercise(
                    id: slotID(index, slot),
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    deletedAt: nil,
                    routineID: routineID,
                    exerciseID: slotID(index, slot),
                    order: slot)
            }
        }

        func routineExercise(id: UUID, includingDeleted: Bool) async throws -> RoutineExercise? {
            nil
        }

        func save(_ exercise: RoutineExercise) async throws {}

        func deleteRoutineExercise(id: UUID) async throws {}

        func targetGroups(
            forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
        ) async throws -> [RoutineTargetGroup] {
            guard let position = slotIndex(of: routineExerciseID) else { return [] }
            return days[position.day].slots[position.slot].groups.enumerated()
                .map { index, group in
                    RoutineTargetGroup(
                        id: deterministic(4, position.slot * 10 + index, position.day),
                        createdAt: .distantPast,
                        updatedAt: .distantPast,
                        deletedAt: nil,
                        routineExerciseID: routineExerciseID,
                        order: index,
                        targetWeight: group.grams.map { Weight(grams: $0) },
                        targetReps: group.reps,
                        targetSets: group.sets)
                }
        }

        func save(_ group: RoutineTargetGroup) async throws {}

        func deleteTargetGroup(id: UUID) async throws {}

    }

    extension WeekFixture: ExerciseRepository {
        func exercises(includingDeleted: Bool) async throws -> [Exercise] { [] }

        func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
            guard let position = slotIndex(of: id) else { return nil }
            return Exercise(
                id: id,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                name: days[position.day].slots[position.slot].name,
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

        func save(_ exercise: Exercise) async throws {}

        func trainingMax(
            forExerciseID exerciseID: UUID, on date: Date
        ) async throws -> TrainingMaxEntry? { nil }

        func trainingMaxHistory(
            forExerciseID exerciseID: UUID, includingDeleted: Bool
        ) async throws -> [TrainingMaxEntry] { [] }

        func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {}

    }

    extension WeekFixture: SettingsRepository {
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

        func restorePreferences(from backup: UserSettings) async throws {}
    }

#endif
