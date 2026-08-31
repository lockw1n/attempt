import Foundation
import Testing

@testable import RepositoryInterface

// `FR-1.14.2`: which of an exercise's two names a screen shows, and what it shows when the second
// one is missing. Every expectation is anchored to a literal rather than to the record's own
// property — an accessor that returned `nil` for everything would satisfy `resolved == exercise.name`
// on a record whose name is also absent, which is the shape T-0.15 found three of.

@Suite("An exercise resolves a name for the locale (FR-1.14.2)")
struct ExerciseDisplayNameTests {
    private func exercise(ukrainianName: String?) -> Exercise {
        makeExercise(name: "Low-bar back squat", ukrainianName: ukrainianName)
    }

    @Test("Ukrainian shows the Ukrainian name where there is one")
    func ukrainianShowsTheSecondName() {
        let resolved = exercise(ukrainianName: "Присідання").displayName(in: .ukrainian)

        #expect(resolved == "Присідання")
    }

    @Test("English shows the English name even when a Ukrainian one is set")
    func englishIgnoresTheSecondName() {
        let resolved = exercise(ukrainianName: "Присідання").displayName(in: .english)

        #expect(resolved == "Low-bar back squat")
    }

    // The fallback, and the reason the accessor exists at all: T-1.18 translates the catalogue over
    // time, so a partly-translated store is the normal case and not an edge one.
    @Test("Ukrainian falls back to the English name where there is none")
    func ukrainianFallsBack() {
        let resolved = exercise(ukrainianName: nil).displayName(in: .ukrainian)

        #expect(resolved == "Low-bar back squat")
    }

    // Blank and absent are the same answer, which is what lets the form's second field be cleared
    // rather than needing a delete of its own.
    @Test("A blank Ukrainian name is the same as none")
    func blankIsAbsent() {
        #expect(exercise(ukrainianName: "").displayName(in: .ukrainian) == "Low-bar back squat")
        #expect(exercise(ukrainianName: "  \n ").displayName(in: .ukrainian) == "Low-bar back squat")
    }

    @Test("A padded Ukrainian name is shown trimmed")
    func paddedIsTrimmed() {
        let resolved = exercise(ukrainianName: "  Присідання  ").displayName(in: .ukrainian)

        #expect(resolved == "Присідання")
    }

    // `name` is returned as stored, blank included: a blank name is a defect the create form refuses
    // and this accessor must not paper over.
    @Test("A blank English name is not repaired")
    func blankEnglishNameSurvives() {
        let resolved = makeExercise(name: "", ukrainianName: nil).displayName(in: .english)

        #expect(resolved.isEmpty)
    }
}

@Suite("A locale chooses which name (FR-1.14.2)")
struct ExerciseNameLanguageTests {
    // The whole point of matching on the language: `en_GB`'s *region* is the United Kingdom, which
    // is the confusion the column is named `ukrainianName` to avoid and the one a `uk` prefix test
    // against the locale identifier would get wrong in the other direction.
    @Test(
        "Every Ukrainian locale resolves to Ukrainian and nothing else does",
        arguments: [
            ("uk", ExerciseNameLanguage.ukrainian),
            ("uk_UA", .ukrainian),
            ("uk-UA", .ukrainian),
            ("en", .english),
            ("en_US", .english),
            ("en_GB", .english),
            ("de_DE", .english),
            ("ru_RU", .english),
        ])
    func localeChoosesTheLanguage(identifier: String, expected: ExerciseNameLanguage) {
        #expect(ExerciseNameLanguage(Locale(identifier: identifier)) == expected)
    }

    @Test("The locale accessor agrees with the language one")
    func localeAccessorMatches() {
        let exercise = makeExercise(name: "Low-bar back squat", ukrainianName: "Присідання")

        #expect(exercise.displayName(for: Locale(identifier: "uk_UA")) == "Присідання")
        #expect(exercise.displayName(for: Locale(identifier: "en_GB")) == "Low-bar back squat")
    }

    @Test("There are two languages, which is how many names a row holds")
    func languageCountMatchesTheSchema() {
        #expect(ExerciseNameLanguage.allCases.count == 2)
    }
}
