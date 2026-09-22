import Testing

@testable import Logging

/// What the Log sheet gives up at an accessibility type size so that Weight and Reps are both on
/// screen when it opens (`FR-18.6.9`, `Q-18.12`).
///
/// **The switch only.** What it decides is a height and a keyboard, neither readable from here: the
/// heights are `LogSheetHeightTests`' budgets and the keyboard is a simulator reading, recorded
/// in `T-18.21`'s task file. This is the one place the *rule* can fail on its own.
@Suite("How much room the Log sheet has")
struct SetEditorRoomTests {
    @Test("A checklist row's sheet at an accessibility size has room for Weight and Reps only")
    func aRowAtAnAccessibilitySizeIsShortOfRoom() {
        #expect(SetEditorRoom.at(isRow: true, isAccessibilitySize: true) == .forWeightAndReps)
    }

    @Test("At every other size a checklist row's sheet pins everything")
    func aRowAtTheDefaultSizeHasRoomForEverything() {
        #expect(SetEditorRoom.at(isRow: true, isAccessibilitySize: false) == .forEverything)
    }

    @Test("A free workout's sheet pays nothing at either size (OUT-18.6)")
    func theFreeWorkoutIsUntouched() {
        #expect(SetEditorRoom.at(isRow: false, isAccessibilitySize: true) == .forEverything)
        #expect(SetEditorRoom.at(isRow: false, isAccessibilitySize: false) == .forEverything)
    }

    @Test("Both halves move together: the skip scrolls and the keyboard waits")
    func theTwoConsequencesAgree() {
        // Asserted against literals rather than against each other — `a == b` over two properties
        // of one value is satisfied by inverting both, which is the one change that would give
        // back the 132 pt and then spend 306 pt of it on the pad.
        #expect(SetEditorRoom.forWeightAndReps.pinsTheSkip == false)
        #expect(SetEditorRoom.forWeightAndReps.takesTheKeyboardOnOpen == false)
        #expect(SetEditorRoom.forEverything.pinsTheSkip == true)
        #expect(SetEditorRoom.forEverything.takesTheKeyboardOnOpen == true)
    }
}
