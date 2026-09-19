import Foundation
import Testing

@testable import RepositoryInterface

// `FR-18.1.1`: a name matches when it contains every word typed, in any order. Every expectation is
// a literal `true` or `false`, and the suite holds both — a rule forced to either constant fails
// here, and so does one that asks for *any* word rather than every word.

@Suite("A search matches every typed word (FR-18.1.1, FR-1.14.3)")
struct ExerciseNameSearchTests {
    private let cableRow = "Тяга верхнього блока вузьким хватом"

    @Test("Two words find a name holding both")
    func twoWordsFindTheName() {
        #expect(ExerciseNameSearch.matches(cableRow, query: "тяга блока") == true)
    }

    @Test("The words may come in any order")
    func orderDoesNotMatter() {
        #expect(ExerciseNameSearch.matches(cableRow, query: "блока тяга") == true)
    }

    @Test("A name missing one of the words is not found, though it holds the other")
    func everyWordMustAppear() {
        #expect(ExerciseNameSearch.matches(cableRow, query: "тяга штанга") == false)
        #expect(ExerciseNameSearch.matches(cableRow, query: "штанга тяга") == false)
    }

    @Test("One word is a substring search, as it always was")
    func oneWordIsASubstring() {
        #expect(ExerciseNameSearch.matches(cableRow, query: "верхн") == true)
        #expect(ExerciseNameSearch.matches(cableRow, query: "штанга") == false)
    }

    @Test("Case and diacritics still fold, in every word")
    func caseAndDiacriticsFold() {
        #expect(ExerciseNameSearch.matches("Sumó Deadlift", query: "DEADLIFT sumo") == true)
        #expect(ExerciseNameSearch.matches(cableRow, query: "ТЯГА Блока") == true)
    }

    @Test("Whitespace-only input is no search at all")
    func whitespaceIsNoSearch() {
        #expect(ExerciseNameSearch.matches(cableRow, query: "") == true)
        #expect(ExerciseNameSearch.matches(cableRow, query: "   ") == true)
        #expect(ExerciseNameSearch.matches(cableRow, query: " \n\t") == true)
    }

    // A run of spaces between words, or one trailing, must be no word at all. As an empty word that
    // *excluded* everything, the first space typed would empty the list; as one that *matched*
    // everything, it would be harmless only because of the other words — so each case carries a word
    // that must still exclude.
    @Test("Two spaces between words, and a trailing space, are not a word")
    func extraSpacesAreNotAWord() {
        #expect(ExerciseNameSearch.matches(cableRow, query: "тяга  блока") == true)
        #expect(ExerciseNameSearch.matches(cableRow, query: "тяга ") == true)
        #expect(ExerciseNameSearch.matches(cableRow, query: "  блока   тяга  ") == true)
        #expect(ExerciseNameSearch.matches(cableRow, query: "тяга  штанга") == false)
        #expect(ExerciseNameSearch.matches(cableRow, query: "штанга ") == false)
    }

    @Test("A word must appear as typed — an inflected form is not found")
    func inflectionIsNotMatched() {
        #expect(ExerciseNameSearch.matches("Тяга на задню дельту", query: "задня") == false)
    }
}
