import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

@Suite("ExerciseEntity")
struct ExerciseEntityTests {
    // TR-0.2.2: reordering a case must not rewrite history. Asserted against literals rather than
    // against `Movement.squat.rawValue`, which would pass just as happily if the column held an
    // ordinal or a `String(describing:)` rendering.
    @Test("The vocabulary columns hold raw spellings, and each lands in its own column")
    func vocabularyColumnsHoldRawSpellings() {
        let exercise = ExerciseEntity(
            name: "Single-arm Trap Bar Row",
            movement: .row,
            equipment: .dumbbell,
            laterality: .unilateral,
            barType: .trap,
            isCustom: true
        )

        #expect(exercise.movementRawValue == "row")
        #expect(exercise.equipmentRawValue == "dumbbell")
        #expect(exercise.lateralityRawValue == "unilateral")
        #expect(exercise.barTypeRawValue == "trap")
    }

    @Test("Every field survives a save and a re-read")
    func roundTrips() throws {
        let context = try makeTrainingContext()
        let parent = UUID()
        let exercise = ExerciseEntity(
            name: "Dumbbell Bench Press",
            movement: .bench,
            equipment: .dumbbell,
            laterality: .bilateral,
            barType: .noBar,
            isCustom: true,
            implementCount: 2,
            parentExerciseID: parent,
            isArchived: true,
            notes: "competition grip"
        )
        context.insert(exercise)
        try context.saveStamped()

        let stored = try #require(try context.fetch(FetchDescriptor<ExerciseEntity>.notDeleted()).first)

        #expect(stored.name == "Dumbbell Bench Press")
        #expect(stored.movementRawValue == "bench")
        #expect(stored.equipmentRawValue == "dumbbell")
        #expect(stored.lateralityRawValue == "bilateral")
        #expect(stored.barTypeRawValue == "noBar")
        #expect(stored.isCustom)
        #expect(stored.implementCount == 2)
        #expect(stored.parentExerciseID == parent)
        #expect(stored.isArchived)
        #expect(stored.notes == "competition grip")
    }

    // The mitigation the whole unknown-value design rests on: `Laterality` throws on an unrecognised
    // spelling by design, and a throw that reached the row would lose the history that the `.other`
    // fallbacks on the other three types exist to protect. Storing the raw string is what removes
    // the throw — this pins that a value no case answers to costs nothing but its own mapping.
    @Test("A laterality no case answers to leaves the rest of the row intact")
    func unrecognisedLateralitySurvives() throws {
        let context = try makeTrainingContext()
        let exercise = makeSquat(name: "Contralateral Something")
        exercise.lateralityRawValue = "quadrilateral"
        context.insert(exercise)
        try context.saveStamped()

        let stored = try #require(try context.fetch(FetchDescriptor<ExerciseEntity>.notDeleted()).first)

        #expect(stored.lateralityRawValue == "quadrilateral")
        #expect(Laterality(rawValue: stored.lateralityRawValue) == nil)
        #expect(stored.name == "Contralateral Something")
        #expect(stored.movementRawValue == "squat")
        #expect(stored.equipmentRawValue == "barbell")
        #expect(stored.barTypeRawValue == "standard")
    }

    // Gap §9's schema half. `Equipment` plus `Laterality` cannot supply this: a two-dumbbell bench
    // and a barbell bench are both bilateral, and a goblet squat is bilateral with one dumbbell.
    @Test("Implement count is not derivable from equipment or laterality")
    func implementCountIsItsOwnAxis() {
        let barbellBench = ExerciseEntity(
            name: "Bench Press",
            movement: .bench,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            isCustom: false
        )
        let dumbbellBench = ExerciseEntity(
            name: "Dumbbell Bench Press",
            movement: .bench,
            equipment: .dumbbell,
            laterality: .bilateral,
            barType: .noBar,
            isCustom: false,
            implementCount: 2
        )
        let gobletSquat = ExerciseEntity(
            name: "Goblet Squat",
            movement: .squat,
            equipment: .dumbbell,
            laterality: .bilateral,
            barType: .noBar,
            isCustom: false
        )

        #expect(barbellBench.implementCount == 1)
        #expect(dumbbellBench.implementCount == 2)
        #expect(gobletSquat.implementCount == 1)
        // Anchored to literals on both sides: comparing the two rows with each other would agree
        // just as happily if either column read back empty.
        #expect(dumbbellBench.equipmentRawValue == "dumbbell")
        #expect(gobletSquat.equipmentRawValue == "dumbbell")
        #expect(dumbbellBench.lateralityRawValue == "bilateral")
        #expect(gobletSquat.lateralityRawValue == "bilateral")
    }

    // G-1.3 and archiving answer different questions: an archived exercise is hidden from pickers
    // and still readable, a deleted one is out of every default read.
    @Test("Archiving is not deletion")
    func archivingIsNotDeletion() throws {
        let context = try makeTrainingContext()
        let exercise = makeSquat()
        exercise.isArchived = true
        context.insert(exercise)
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<ExerciseEntity>.notDeleted()).first
        )

        #expect(stored.isArchived)
        #expect(stored.deletedAt == nil)
        #expect(stored.isSoftDeleted == false)
    }
}
