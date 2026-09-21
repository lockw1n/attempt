import SwiftUI
import Testing

@testable import Logging

/// What the Log sheet's load does when it takes the keyboard (`FR-18.6.1`).
///
/// **The two rules only, because neither the focus nor the selection is readable from here.**
/// Nothing in a test bundle sees UIKit focus, and a hosted accessibility tree answers whether a
/// control exists rather than what it holds — so *whether focus takes at the detent this sheet
/// opens at* is a simulator measurement, recorded in `T-18.11`'s task file, and what is testable is
/// the pair of decisions the screen applies once it has.
@Suite("Opening the Log sheet on the load")
struct SetEditorFocusTests {
    @Test("The first time the load takes the keyboard is the sheet opening")
    func openingIsTheFirstFocus() {
        #expect(SetEditorFocus.isOpening(isFocused: true, hasOpened: false))
    }

    @Test("Tapping back into the load later is not an open")
    func aLaterTapIsNotAnOpen() {
        #expect(SetEditorFocus.isOpening(isFocused: true, hasOpened: true) == false)
    }

    @Test("Losing the keyboard is not an open, whether or not the sheet has opened")
    func losingFocusIsNotAnOpen() {
        #expect(SetEditorFocus.isOpening(isFocused: false, hasOpened: false) == false)
        #expect(SetEditorFocus.isOpening(isFocused: false, hasOpened: true) == false)
    }

    @Test("A prefilled load opens with the whole of it selected")
    func aPrefilledLoadIsSelectedWhole() throws {
        let text = "110"
        let selection = try #require(SetEditorFocus.selectionOnOpen(of: text))
        #expect(selection.indices == .selection(text.startIndex..<text.endIndex))
        #expect(selection.isInsertion == false)
    }

    @Test("A load written with the locale's own decimal comma is selected whole too")
    func aDecimalLoadIsSelectedWhole() throws {
        let text = "102,5"
        let selection = try #require(SetEditorFocus.selectionOnOpen(of: text))
        #expect(selection.indices == .selection(text.startIndex..<text.endIndex))
    }

    @Test("A plan with no load selects nothing rather than an empty range")
    func anEmptyLoadSelectsNothing() {
        #expect(SetEditorFocus.selectionOnOpen(of: "") == nil)
    }
}
