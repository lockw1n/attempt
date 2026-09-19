import Foundation
import Testing

@testable import Dashboard

/// `FR-16.5.3`: the picker lists trained exercises first, each with its last-trained date, then the
/// rest, with a search field.
@MainActor
@Suite("Exercise picker sections")
struct ExerciseChoiceSectionsTests {
    @Test("Trained rows lead, most recently trained first, and the rest keep the name order")
    func trainedRowsLead() {
        let sections = ExerciseChoiceSections.sections(
            [
                choice("Barbell Row", daysAgo: nil),
                choice("Bench Press", daysAgo: 9),
                choice("Deadlift", daysAgo: nil),
                choice("Front Squat", daysAgo: 2),
            ],
            matching: "")

        #expect(sections.map(\.kind) == [.trained, .everythingElse])
        #expect(names(sections[0]) == ["Front Squat", "Bench Press"])
        #expect(names(sections[1]) == ["Barbell Row", "Deadlift"])
    }

    /// A session dates a training *day*, so two exercises trained in the same workout are exactly as
    /// recent as each other — which makes the tiebreak the common case rather than the freak one.
    @Test("Two exercises trained on the same day are ordered by name")
    func sameDayTiesBreakOnTheName() {
        let sections = ExerciseChoiceSections.sections(
            [
                choice("Zercher Squat", daysAgo: 4),
                choice("Bench Press", daysAgo: 4),
                choice("Overhead Press", daysAgo: 4),
            ],
            matching: "")

        #expect(names(sections[0]) == ["Bench Press", "Overhead Press", "Zercher Squat"])
    }

    @Test("A search narrows both sections, not only the untrained one")
    func searchNarrowsBothSections() {
        let choices = [
            choice("Barbell Row", daysAgo: nil),
            choice("Bench Press", daysAgo: 3),
            choice("Front Squat", daysAgo: 1),
            choice("Squat Machine", daysAgo: nil),
        ]

        let sections = ExerciseChoiceSections.sections(choices, matching: "squat")

        #expect(names(sections[0]) == ["Front Squat"])
        #expect(names(sections[1]) == ["Squat Machine"])
    }

    @Test("A section a search empties is dropped rather than drawn with no rows under it")
    func anEmptiedSectionIsDropped() {
        let choices = [
            choice("Bench Press", daysAgo: 3),
            choice("Barbell Row", daysAgo: nil),
        ]

        #expect(ExerciseChoiceSections.sections(choices, matching: "bench").map(\.kind) == [.trained])
        #expect(
            ExerciseChoiceSections.sections(choices, matching: "row").map(\.kind)
                == [.everythingElse])
        #expect(ExerciseChoiceSections.sections(choices, matching: "curl").isEmpty)
    }

    /// Otherwise the first space typed empties the screen.
    @Test("Whitespace is no search at all")
    func whitespaceIsNoSearch() {
        let choices = [choice("Bench Press", daysAgo: 3), choice("Barbell Row", daysAgo: nil)]

        #expect(ExerciseChoiceSections.sections(choices, matching: "   ").count == 2)
    }

    /// Any-word would also find "Bench Press"; one substring would find nothing.
    @Test("The search matches every typed word, in any order (FR-18.1.1)")
    func searchMatchesEveryWord() {
        let choices = [
            choice("Bench Press", daysAgo: 3),
            choice("Close-Grip Bench Press", daysAgo: nil),
            choice("Barbell Row", daysAgo: nil),
        ]

        let found = ExerciseChoiceSections.sections(choices, matching: "bench  grip ")
        #expect(found.map(\.kind) == [.everythingElse])
        #expect(found.flatMap(names) == ["Close-Grip Bench Press"])
    }

    /// `FR-1.14.3` says the name shown, and `localizedStandardContains` is what makes a query
    /// without diacritics find one with them.
    @Test("The search ignores case and diacritics")
    func searchIgnoresCaseAndDiacritics() {
        let choices = [choice("Sumó Deadlift", daysAgo: nil)]

        #expect(names(ExerciseChoiceSections.sections(choices, matching: "SUMO")[0]) == ["Sumó Deadlift"])
    }

    /// `FR-18.1.2` inside **Everything else**, over rows handed in already in the rule's order for
    /// the whole catalogue — so the section must re-order what is left, not keep what it was given.
    @Test("Everything else leads with a parent, and a variation whose parent is elsewhere is a root")
    func everythingElseOrdersParentFirstOverWhatItHolds() {
        let back = UUID()
        let bench = UUID()
        let catalogue = [
            choice("Air Squat", daysAgo: nil),
            choice("Back Squat", id: back, daysAgo: 2),
            choice("Box Squat", parent: back, daysAgo: nil),
            choice("Tempo Squat", parent: back, daysAgo: nil),
            choice("Bench Press", id: bench, daysAgo: nil),
            choice("Close-Grip Bench", parent: bench, daysAgo: nil),
            choice("Hack Squat", daysAgo: nil),
        ]

        let sections = ExerciseChoiceSections.sections(catalogue, matching: "")
        #expect(names(sections[0]) == ["Back Squat"])
        #expect(
            names(sections[1]) == [
                "Air Squat", "Bench Press", "Close-Grip Bench", "Box Squat", "Hack Squat",
                "Tempo Squat",
            ])

        let searched = ExerciseChoiceSections.sections(catalogue, matching: "bench")
        #expect(searched.map(\.kind) == [.everythingElse])
        #expect(names(searched[0]) == ["Bench Press", "Close-Grip Bench"])

        let squats = ExerciseChoiceSections.sections(catalogue, matching: "squat")
        #expect(names(squats[1]) == ["Air Squat", "Box Squat", "Hack Squat", "Tempo Squat"])
    }

    /// One row, trained `daysAgo` days before ``fixtureNow`` or not at all.
    private func choice(
        _ name: String, id: UUID = UUID(), parent: UUID? = nil, daysAgo: Int?
    ) -> TiledExerciseChoice {
        TiledExerciseChoice(
            exerciseID: id,
            name: name,
            parentExerciseID: parent,
            isTiled: false,
            lastTrained: daysAgo.map { fixtureNow.addingTimeInterval(-Double($0) * 86_400) })
    }

    /// The names in one section, in the order it holds them.
    private func names(_ section: ExerciseChoiceSection) -> [String] {
        section.choices.map(\.name)
    }
}
