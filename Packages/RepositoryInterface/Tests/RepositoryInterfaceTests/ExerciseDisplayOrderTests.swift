import Foundation
import Testing

@testable import RepositoryInterface

// `FR-18.1.2`: a parent is followed by its variations, alphabetical within. Every expectation is a
// literal list of names, so a sort that returns its input fails here, and so does plain name order
// — the first test's two lists differ, and `Hack squat` is the row that tells them apart.

@Suite("A parent precedes its variations (FR-18.1.2, FR-1.14.2)")
struct ExerciseDisplayOrderTests {
    private func names(_ exercises: [Exercise], in language: ExerciseNameLanguage = .english) -> [String] {
        ExerciseDisplayOrder.sorted(exercises, in: language).map { $0.displayName(in: language) }
    }

    @Test("Each root is followed by its variations, by name, before the next root")
    func variationsFollowTheirParent() {
        let back = makeExercise(name: "Back squat")
        let catalogue = [
            makeExercise(name: "Zercher squat"),
            makeExercise(name: "Tempo squat", parentExerciseID: back.id),
            makeExercise(name: "Hack squat"),
            makeExercise(name: "Pause squat", parentExerciseID: back.id),
            back,
            makeExercise(name: "Box squat", parentExerciseID: back.id),
            makeExercise(name: "Air squat"),
        ]
        #expect(
            names(catalogue) == [
                "Air squat", "Back squat", "Box squat", "Pause squat", "Tempo squat", "Hack squat",
                "Zercher squat",
            ])
    }

    @Test("The tester's search: plain squat leads its variations, not the other way round")
    func testersSearchReadsParentFirst() {
        let back = makeExercise(name: "Back Squat", ukrainianName: "Присідання зі штангою")
        let catalogue = [
            makeExercise(
                name: "High-Bar Squat",
                ukrainianName: "Присідання з високим грифом",
                parentExerciseID: back.id),
            makeExercise(
                name: "Pause Squat", ukrainianName: "Присідання з паузою", parentExerciseID: back.id),
            back,
            makeExercise(name: "Hack Squat", ukrainianName: "Присідання в гакк-машині"),
        ]
        #expect(
            names(catalogue, in: .ukrainian) == [
                "Присідання в гакк-машині", "Присідання зі штангою", "Присідання з високим грифом",
                "Присідання з паузою",
            ])
    }

    @Test("A variation whose parent is not in the input sorts among the roots by its own name")
    func orphanSortsAsARoot() {
        let absentParent = UUID()
        let catalogue = [
            makeExercise(name: "Front squat"),
            makeExercise(name: "Pause squat", parentExerciseID: absentParent),
            makeExercise(name: "Air squat"),
        ]
        #expect(names(catalogue) == ["Air squat", "Front squat", "Pause squat"])
    }

    @Test("A variation of a variation joins its root's run, in name order with the rest")
    func twoDeepChainIsOneFlatRun() {
        let deadlift = makeExercise(name: "Deadlift")
        let deficit = makeExercise(name: "Deficit deadlift", parentExerciseID: deadlift.id)
        let catalogue = [
            makeExercise(name: "Rack pull"),
            makeExercise(name: "Block pull", parentExerciseID: deadlift.id),
            makeExercise(name: "Banded deficit deadlift", parentExerciseID: deficit.id),
            deficit,
            deadlift,
            makeExercise(name: "Good morning"),
        ]
        #expect(
            names(catalogue) == [
                "Deadlift", "Banded deficit deadlift", "Block pull", "Deficit deadlift", "Good morning",
                "Rack pull",
            ])
    }

    @Test("A cycle terminates, keeps every row, and puts a row hanging off it in a run", .timeLimit(.minutes(1)))
    func cycleTerminates() {
        let alphaID = UUID()
        let betaID = UUID()
        let catalogue = [
            makeExercise(id: betaID, name: "Beta", parentExerciseID: alphaID),
            makeExercise(name: "Gamma", parentExerciseID: alphaID),
            makeExercise(id: alphaID, name: "Alpha", parentExerciseID: betaID),
            makeExercise(name: "Delta", parentExerciseID: betaID),
            makeExercise(name: "Aardvark"),
        ]
        // Alpha and Beta are each other's parent, so both are roots; Gamma and Delta hang off them.
        #expect(names(catalogue) == ["Aardvark", "Alpha", "Gamma", "Beta", "Delta"])
    }

    @Test("A row that is its own parent is a root")
    func selfParentIsARoot() {
        let loopID = UUID()
        let catalogue = [
            makeExercise(id: loopID, name: "Loop", parentExerciseID: loopID),
            makeExercise(name: "Child", parentExerciseID: loopID),
            makeExercise(name: "Apple"),
        ]
        #expect(names(catalogue) == ["Apple", "Loop", "Child"])
    }

    @Test("Two rows reading alike break the tie on the identifier, among roots and within a run")
    func sameNameBreaksOnIdentifier() throws {
        let low = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let childLow = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let childHigh = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        let catalogue = [
            makeExercise(id: childHigh, name: "Pause squat", parentExerciseID: high),
            makeExercise(id: high, name: "Squat"),
            makeExercise(id: childLow, name: "Pause squat", parentExerciseID: high),
            makeExercise(id: low, name: "Squat"),
        ]
        #expect(
            ExerciseDisplayOrder.sorted(catalogue, in: .english).map(\.id) == [
                low, high, childLow, childHigh,
            ])
    }

    @Test("A row stored twice under one identifier keeps both copies and does not repeat its run")
    func duplicatedRootDoesNotRepeatItsRun() {
        let back = makeExercise(name: "Back squat")
        let pause = makeExercise(name: "Pause squat", parentExerciseID: back.id)
        let catalogue = [pause, back, makeExercise(name: "Hack squat"), pause, back]
        #expect(
            names(catalogue) == ["Back squat", "Back squat", "Pause squat", "Pause squat", "Hack squat"])
    }
}
