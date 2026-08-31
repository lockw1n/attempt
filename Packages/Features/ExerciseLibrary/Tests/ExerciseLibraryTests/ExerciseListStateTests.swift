import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.1.1`/`FR-1.1.2` as claims about *results*: what the list shows, for a search and a set of
/// filters. Every one of them is answered without rendering a view, which is the property `TR-1.2`'s
/// pattern exists to buy.
@MainActor
@Suite("Exercise list state")
struct ExerciseListStateTests {
    // MARK: - Reading

    @Test("A load publishes the catalogue")
    func loadPublishesCatalogue() async {
        let state = ExerciseListState.overCatalogue(ScriptedExerciseRepository(exercises: Fixtures.catalogue))
        await state.load()
        // Grouped order, not alphabetical: `names` reads the groups, and the groups follow
        // Movement's case order with each one sorted by name inside it.
        #expect(state.names == ["Back Squat", "Front Squat", "Bench Press", "Sumo Deadlift", "Barbell Row"])
    }

    @Test("Archived exercises are out of the list unless they are asked for (FR-1.1.5)")
    func archivedExercisesAreExcluded() async {
        let archived = Fixtures.exercise(name: "Retired Machine Press", movement: .bench, isArchived: true)
        let state = ExerciseListState.overCatalogue(
            ScriptedExerciseRepository(exercises: Fixtures.catalogue + [archived])
        )
        await state.load()
        #expect(!state.names.contains("Retired Machine Press"))
        #expect(state.names.count == 5)
    }

    @Test("Soft-deleted rows are asked for by the repository call, not filtered afterwards")
    func deletedRowsAreNotRequested() async {
        let repository = ScriptedExerciseRepository(exercises: Fixtures.catalogue)
        let state = ExerciseListState.overCatalogue(repository)
        await state.load()
        #expect(await repository.readsIncludingDeleted == [false])
    }

    @Test("A failed read is recoverable, and the retry reloads")
    func failedReadRetries() async {
        let repository = ScriptedExerciseRepository(
            exercises: Fixtures.catalogue,
            readError: .recordNotFound(id: UUID())
        )
        let state = ExerciseListState.overCatalogue(repository)
        await state.load()
        guard case .failed(let diagnostic) = state.phase else {
            Issue.record("expected a failed phase, got \(state.phase)")
            return
        }
        #expect(diagnostic.contains("recordNotFound"))
        #expect(state.groups.isEmpty)

        await repository.recover()
        await state.load()
        #expect(state.names.count == 5)
    }

    @Test("A catalogue already loaded is not read again")
    func loadedCatalogueIsNotReRead() async {
        let repository = ScriptedExerciseRepository(exercises: Fixtures.catalogue)
        let state = ExerciseListState.overCatalogue(repository)
        await state.load()
        await state.load()
        #expect(await repository.reads == 1)
    }

    // MARK: - Grouping

    @Test("Groups follow Movement's own order, and a movement with nothing in it is dropped")
    func groupsAreOrderedAndSparse() async {
        let state = await Fixtures.loaded()
        #expect(state.groups.map(\.movement) == [.squat, .bench, .deadlift, .row])
        #expect(state.groups.map { $0.exercises.count } == [2, 1, 1, 1])
    }

    @Test("Within a group, exercises are ordered by name")
    func groupsAreSortedByName() async {
        let state = await Fixtures.loaded()
        let squats = state.groups.first { $0.movement == .squat }
        #expect(squats?.exercises.map(\.name) == ["Back Squat", "Front Squat"])
    }

    @Test("Two exercises sharing a name are ordered by identifier, so a rendering never moves")
    func sharedNamesAreBrokenByIdentifier() async {
        // FR-1.1.4 renames without restriction and G-2.5 forbids a unique constraint on the name,
        // so two rows reading "Belt Squat" is a state the store permits. Handed to the repository
        // in the wrong order, so the assertion is about `browsable` and not about the fake.
        let first = Fixtures.exercise(id: Fixtures.identifier("A"), name: "Belt Squat", movement: .squat)
        let second = Fixtures.exercise(id: Fixtures.identifier("B"), name: "Belt Squat", movement: .squat)
        let state = ExerciseListState.overCatalogue(
            ScriptedExerciseRepository(exercises: [second, first])
        )
        await state.load()
        #expect(state.groups.first?.exercises.map(\.id) == [first.id, second.id])
    }

    // MARK: - Search (FR-1.1.1)

    @Test("Search matches part of a name, ignoring case")
    func searchIgnoresCase() async {
        let state = await Fixtures.loaded()
        state.searchText = "squat"
        #expect(state.names == ["Back Squat", "Front Squat"])
    }

    @Test("Search ignores diacritics")
    func searchIgnoresDiacritics() async {
        let state = ExerciseListState.overCatalogue(
            ScriptedExerciseRepository(
                exercises: [Fixtures.exercise(name: "Sumó Deadlift", movement: .deadlift)]
            )
        )
        await state.load()
        state.searchText = "sumo"
        #expect(state.names == ["Sumó Deadlift"])
    }

    @Test("Whitespace is not a search")
    func whitespaceIsNotASearch() async {
        let state = await Fixtures.loaded()
        state.searchText = "   "
        #expect(state.names.count == 5)
    }

    @Test("A search that matches nothing empties the groups without emptying the catalogue")
    func unmatchedSearchIsNotAnEmptyCatalogue() async {
        let state = await Fixtures.loaded()
        state.searchText = "kettlebell juggling"
        #expect(state.groups.isEmpty)
        #expect(!state.isCatalogueEmpty)
    }

    // MARK: - Filters (FR-1.1.2)

    @Test("The movement filter narrows to one movement")
    func movementFilterNarrows() async {
        let state = await Fixtures.loaded()
        state.movementFilter = .deadlift
        #expect(state.names == ["Sumo Deadlift"])
        #expect(state.groups.map(\.movement) == [.deadlift])
    }

    @Test("The equipment filter narrows to one implement")
    func equipmentFilterNarrows() async {
        let state = await Fixtures.loaded()
        state.equipmentFilter = .dumbbell
        #expect(state.names == ["Bench Press"])
    }

    @Test("The origin filter separates the user's exercises from the seeded ones")
    func originFilterSeparatesCustomFromBuiltIn() async {
        let state = await Fixtures.loaded()
        state.originFilter = .custom
        #expect(state.names == ["Front Squat"])
        state.originFilter = .builtIn
        #expect(state.names == ["Back Squat", "Bench Press", "Sumo Deadlift", "Barbell Row"])
    }

    @Test("Filters and search compose")
    func filtersCompose() async {
        let state = await Fixtures.loaded()
        state.movementFilter = .squat
        state.originFilter = .builtIn
        #expect(state.names == ["Back Squat"])
        state.searchText = "front"
        #expect(state.names.isEmpty)
    }

    @Test("Clearing puts every control back and the whole catalogue with it")
    func clearingRestoresTheCatalogue() async {
        let state = await Fixtures.loaded()
        state.searchText = "squat"
        state.movementFilter = .squat
        state.equipmentFilter = .barbell
        state.originFilter = .builtIn
        // Anchored to the result rather than to a "something is set" flag: what clearing has to put
        // back is the catalogue, so what it is cleared FROM has to be a narrowing that happened.
        #expect(state.names == ["Back Squat"])

        state.clearFilters()
        #expect(state.searchText.isEmpty)
        #expect(state.movementFilter == nil)
        #expect(state.equipmentFilter == nil)
        #expect(state.originFilter == nil)
        #expect(state.names.count == 5)
    }

    @Test("Recency is not offered while nothing has been trained (FR-1.1.2)")
    func recencyFilterIsUnavailable() async {
        let state = await Fixtures.loaded()
        #expect(state.isRecencyFilterAvailable == false)
        // The rest of FR-1.1.2's recency filter is in `ExerciseRecencyTests`, which is where the
        // workout repository behind it is written into.
    }

    // MARK: - The three empties (FR-1.13.1)

    @Test("An empty catalogue is a loaded state, not a missing one")
    func emptyCatalogueIsALoadedState() async {
        let state = ExerciseListState.overCatalogue(ScriptedExerciseRepository(exercises: []))
        await state.load()
        #expect(state.isCatalogueEmpty)
        #expect(state.groups.isEmpty)
    }

    /// T-1.10 asserted `isCatalogueEmpty` here, when archived rows were dropped on the way out of
    /// the read and nothing could tell a hidden catalogue from an absent one. `FR-1.1.5`'s control
    /// separates them: the rows are there, and the answer is the state that names the control rather
    /// than the one that offers a create form. `ExerciseArchiveTests` has the rest of the split.
    @Test("A catalogue whose every row is archived is hidden, not empty")
    func fullyArchivedCatalogueIsHidden() async {
        let state = ExerciseListState.overCatalogue(
            ScriptedExerciseRepository(
                exercises: [Fixtures.exercise(name: "Retired", movement: .other, isArchived: true)]
            )
        )
        await state.load()
        #expect(!state.isCatalogueEmpty)
        #expect(state.isEverythingArchived)
        #expect(state.groups.isEmpty)
    }

    @Test("Nothing is claimed to be empty before a read has finished")
    func nothingIsEmptyBeforeLoading() {
        let state = ExerciseListState.overCatalogue(ScriptedExerciseRepository(exercises: []))
        #expect(state.phase == .idle)
        #expect(!state.isCatalogueEmpty)
        #expect(!state.isEverythingArchived)
        #expect(state.groups.isEmpty)
    }

    // MARK: - Refreshing (FR-1.1.3, FR-1.1.4)

    @Test("A refresh shows an exercise created since the list was read")
    func refreshPicksUpANewExercise() async throws {
        let repository = ScriptedExerciseRepository(exercises: Fixtures.catalogue)
        let state = ExerciseListState.overCatalogue(repository)
        await state.load()
        #expect(state.names.count == 5)

        // What T-1.12's create screen does, one screen above this one.
        try await repository.save(Fixtures.exercise(name: "Belt Squat", movement: .squat))
        await state.refresh()
        #expect(state.names.contains("Belt Squat"))
        #expect(state.names.count == 6)
    }

    @Test("A refresh on a screen that has read nothing yet is the first read")
    func refreshFromIdleLoads() async {
        let repository = ScriptedExerciseRepository(exercises: Fixtures.catalogue)
        let state = ExerciseListState.overCatalogue(repository)
        await state.refresh()
        #expect(state.names.count == 5)
        #expect(await repository.reads == 1)
    }

    @Test("A refresh applies the same exclusions and the same order the first read did")
    func refreshStaysBrowsable() async throws {
        let repository = ScriptedExerciseRepository(exercises: Fixtures.catalogue)
        let state = ExerciseListState.overCatalogue(repository)
        await state.load()
        let firstRead = state.names
        let backSquat = try #require(firstRead.firstIndex(of: "Back Squat"))

        // `refresh()` is a second path to the same rows, so `FR-1.1.5`'s archive exclusion and
        // `FR-1.1.1`'s order have to be pinned on it and not only on `load()`: a refresh that
        // returned the repository's own rows unfiltered would pass every other test in this suite.
        try await repository.save(
            Fixtures.exercise(name: "Retired Squat", movement: .squat, isArchived: true))
        try await repository.save(Fixtures.exercise(name: "Belt Squat", movement: .squat))
        await state.refresh()

        // Directly after Back Squat, which is where its name puts it inside the squat group — not
        // at the end, which is where the read returned it.
        var expected = firstRead
        expected.insert("Belt Squat", at: backSquat + 1)
        #expect(state.names == expected)
        #expect(!state.names.contains("Retired Squat"))
    }

    @Test("A refresh that fails leaves the screen in the state that offers a retry")
    func failedRefreshIsRecoverable() async {
        let repository = ScriptedExerciseRepository(exercises: Fixtures.catalogue)
        let state = ExerciseListState.overCatalogue(repository)
        await state.load()
        await repository.failReads(.recordNotFound(id: UUID()))
        await state.refresh()

        guard case .failed(let diagnostic) = state.phase else {
            Issue.record("expected a failed phase, got \(state.phase)")
            return
        }
        #expect(diagnostic.contains("recordNotFound"))

        await repository.recover()
        await state.refresh()
        #expect(state.names.count == 5)
    }
}

/// Every exercise the list shows, in order — the one read the assertions above are written against.
///
/// Not `fileprivate`: `ExerciseArchiveTests` asks the same question of the same screen, and a second
/// spelling of it in that file is a second thing to keep true.
extension ExerciseListState {
    var names: [String] { groups.flatMap { $0.exercises.map(\.name) } }
}

/// The catalogue these tests browse: five live exercises across four movements, one of them the
/// user's own, one of them on dumbbells.
enum Fixtures {
    /// **Deliberately in no order any assertion expects** — not alphabetical within a movement and
    /// not in `Movement`'s case order across them. A fixture that arrives sorted cannot fail a test
    /// about sorting: measured, removing `browsable`'s `sorted` entirely left this suite green.
    static let catalogue: [Exercise] = [
        exercise(name: "Sumo Deadlift", movement: .deadlift),
        exercise(name: "Front Squat", movement: .squat, isCustom: true),
        exercise(name: "Barbell Row", movement: .row),
        exercise(name: "Back Squat", movement: .squat),
        exercise(name: "Bench Press", movement: .bench, equipment: .dumbbell),
    ]

    /// A state over ``catalogue``, already read.
    static func loaded() async -> ExerciseListState {
        let state = ExerciseListState.overCatalogue(ScriptedExerciseRepository(exercises: catalogue))
        await state.load()
        return state
    }

    /// An identifier ending in `suffix`, for the one assertion whose answer is the byte order of
    /// two of them.
    static func identifier(_ suffix: String) -> UUID {
        UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-00000000000\(suffix)") ?? UUID()
    }

    /// One exercise. Every field the screen does not read is a fixed value, so a test that starts
    /// depending on one is visibly doing so.
    static func exercise(
        id: UUID = UUID(),
        name: String,
        ukrainianName: String? = nil,
        movement: Movement,
        equipment: Equipment = .barbell,
        parentExerciseID: UUID? = nil,
        isCustom: Bool = false,
        isArchived: Bool = false,
        notes: String = ""
    ) -> Exercise {
        Exercise(
            id: id,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            deletedAt: nil,
            name: name,
            ukrainianName: ukrainianName,
            movement: movement,
            parentExerciseID: parentExerciseID,
            equipment: equipment,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: isCustom,
            isArchived: isArchived,
            notes: notes,
            manualE1RM: nil)
    }
}
