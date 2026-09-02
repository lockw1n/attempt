import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.14.2`/`FR-1.14.3` as claims about results: which name a browsable surface orders by, and
/// which one a search is matched against. Every one is asked of a state rather than of a rendering —
/// a row's own text is the environment's to resolve, and a snapshot is what checks that.
///
/// **The Ukrainian names here sort against their English ones on purpose.** "Front Squat" precedes
/// "Back Squat" in Ukrainian and follows it in English, so an implementation that ordered by the
/// stored English column while showing the Ukrainian one fails on the permutation rather than on the
/// strings — which is the failure a reader of the screen would actually see.
@MainActor
@Suite("Exercise names, resolved for the screen's locale")
struct ExerciseLocaleDisplayTests {
    // MARK: - Search (FR-1.14.3)

    @Test("A Ukrainian screen is searched by the Ukrainian name")
    func ukrainianScreenMatchesUkrainianName() async {
        let state = await LocaleFixtures.loaded(.ukrainian)
        state.searchText = "зі штангою"
        #expect(state.displayNames == ["Присідання зі штангою"])

        // A substring both squats share, lower-cased where one of the two names capitalises it:
        // `localizedStandardContains` is the same search Cyrillic that it is in Latin.
        state.searchText = "присідання"
        #expect(state.displayNames == ["Глибокі присідання", "Присідання зі штангою"])
    }

    @Test("The English name behind a Ukrainian row no longer matches — it is not what is shown")
    func ukrainianScreenDoesNotMatchTheHiddenEnglishName() async {
        let state = await LocaleFixtures.loaded(.ukrainian)
        state.searchText = "Back Squat"
        #expect(state.displayNames.isEmpty)
    }

    @Test("An English screen is searched by the English name, and not by the Ukrainian one")
    func englishScreenMatchesEnglishName() async {
        let state = await LocaleFixtures.loaded(.english)
        state.searchText = "Back Squat"
        #expect(state.displayNames == ["Back Squat"])

        state.searchText = "Присідання"
        #expect(state.displayNames.isEmpty)
    }

    @Test("An exercise with no Ukrainian name is found under the English one it falls back to")
    func untranslatedRowIsFoundUnderItsEnglishName() async {
        let state = await LocaleFixtures.loaded(.ukrainian)
        state.searchText = "Barbell Row"
        #expect(state.displayNames == ["Barbell Row"])
    }

    @Test("A Ukrainian name that is only whitespace is neither shown nor searchable as one")
    func whitespaceUkrainianNameIsNotAName() async {
        let state = await LocaleFixtures.loaded(.ukrainian)
        state.searchText = "Bench"
        // The row is the one whose `ukrainianName` is three spaces: it answers to its English name,
        // which is what `displayName(in:)` resolves it to.
        #expect(state.displayNames == ["Bench Press"])

        state.searchText = " "
        // Whitespace is no search at all, so this is the whole catalogue rather than the one row a
        // blank-matching implementation would return.
        #expect(state.displayNames.count == LocaleFixtures.catalogue.count)
    }

    // MARK: - Order (FR-1.14.2)

    @Test("Rows are ordered by the name they show, not by the English column behind it")
    func orderFollowsTheDisplayedName() async {
        let english = await LocaleFixtures.loaded(.english)
        #expect(
            english.displayNames == [
                "Back Squat", "Front Squat", "Bench Press", "Sumo Deadlift", "Barbell Row",
            ])

        let ukrainian = await LocaleFixtures.loaded(.ukrainian)
        #expect(
            ukrainian.displayNames == [
                "Глибокі присідання", "Присідання зі штангою", "Bench Press", "Тяга сумо",
                "Barbell Row",
            ])
    }

    @Test("The language reaches the rows without a second read")
    func languageIsReadDerivedRatherThanBakedIn() async {
        let repository = ScriptedExerciseRepository(exercises: LocaleFixtures.catalogue)
        let state = ExerciseListState.overCatalogue(repository)
        await state.load()
        state.nameLanguage = .ukrainian
        #expect(state.displayNames.first == "Глибокі присідання")
        #expect(await repository.readsIncludingDeleted == [false])
    }

    // MARK: - The other two browsable surfaces

    @Test("A detail screen's variations are ordered by the name their rows show")
    func variationsFollowTheDisplayedName() async {
        let state = DetailFixtures.state(
            exerciseID: LocaleFixtures.parentID,
            repository: ScriptedExerciseRepository(exercises: LocaleFixtures.family))
        state.nameLanguage = .ukrainian
        await state.load()
        guard case .loaded(let detail) = state.phase else {
            Issue.record("expected a loaded phase, got \(state.phase)")
            return
        }
        #expect(
            detail.variations.map { $0.displayName(in: .ukrainian) }
                == ["Глибокі присідання", "Присідання зі штангою"])
    }

    @Test("The parent picker's candidates are ordered by the name their rows show (FR-1.1.7)")
    func parentCandidatesFollowTheDisplayedName() async {
        let state = ExerciseFormState(
            mode: .create,
            repository: ScriptedExerciseRepository(exercises: LocaleFixtures.catalogue))
        state.nameLanguage = .ukrainian
        state.offersEveryMovementAsParent = true
        await state.load()
        #expect(
            state.parentCandidates.map { $0.displayName(in: .ukrainian) } == [
                "Barbell Row", "Bench Press", "Глибокі присідання", "Присідання зі штангою",
                "Тяга сумо",
            ])
    }
}

/// Every name the list is showing, in the order it shows them — the display half of
/// `ExerciseListState.names`, which reads the English column.
extension ExerciseListState {
    var displayNames: [String] {
        groups.flatMap { $0.exercises.map { $0.displayName(in: nameLanguage) } }
    }
}

/// A catalogue whose Ukrainian names sort against its English ones, plus the two rows that make the
/// fallback assertable: one with no Ukrainian name at all, one whose Ukrainian name is whitespace.
enum LocaleFixtures {
    /// The identifier of the exercise the variation rows point at.
    static let parentID = Fixtures.identifier("7")

    /// Five exercises: three translated, one untranslated, one translated to whitespace.
    ///
    /// In no order any assertion expects, on ``Fixtures/catalogue``'s rule.
    static let catalogue: [Exercise] = [
        Fixtures.exercise(name: "Sumo Deadlift", ukrainianName: "Тяга сумо", movement: .deadlift),
        Fixtures.exercise(
            name: "Front Squat", ukrainianName: "Глибокі присідання", movement: .squat),
        Fixtures.exercise(name: "Barbell Row", movement: .row),
        Fixtures.exercise(
            name: "Back Squat", ukrainianName: "Присідання зі штангою", movement: .squat),
        Fixtures.exercise(
            name: "Bench Press",
            ukrainianName: "   ",
            movement: .bench,
            equipment: .dumbbell),
    ]

    /// A root exercise with the two translated squats under it, for the detail screen's order.
    static let family: [Exercise] = [
        Fixtures.exercise(id: parentID, name: "Squat", ukrainianName: "Присідання", movement: .squat),
        Fixtures.exercise(
            name: "Back Squat",
            ukrainianName: "Присідання зі штангою",
            movement: .squat,
            parentExerciseID: parentID),
        Fixtures.exercise(
            name: "Front Squat",
            ukrainianName: "Глибокі присідання",
            movement: .squat,
            parentExerciseID: parentID),
    ]

    /// A list state over ``catalogue``, already read, showing `language`.
    static func loaded(_ language: ExerciseNameLanguage) async -> ExerciseListState {
        let state = ExerciseListState.overCatalogue(ScriptedExerciseRepository(exercises: catalogue))
        state.nameLanguage = language
        await state.load()
        return state
    }
}
