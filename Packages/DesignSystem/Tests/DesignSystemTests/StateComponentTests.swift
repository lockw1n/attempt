import DesignTokens
import Testing

@testable import DesignSystem

/// The five placeholders `FR-1.13.1` and `FR-1.13.3` require, held at the layer a test can reach:
/// which token each state chooses. What they render is T-1.08's snapshot; a wrong choice here is a
/// wrong constant rather than a wrong pixel.
@Suite("State placeholder token choices")
struct StateComponentTests {
    /// Every state that draws a glyph has to be told apart from the others by that glyph alone —
    /// it is the cue that survives a colourblind reader and a monochrome rendering (`G-4.5`), and
    /// two of these states share a tint on purpose.
    @Test("every state that draws a glyph names a distinct, non-empty one")
    func glyphsAreDistinct() {
        let symbols = StateKind.allCases.compactMap(\.symbolName)
        // Anchored to a count rather than to `Set(symbols).count == symbols.count`, which an
        // implementation returning nil everywhere would satisfy with two empty collections.
        #expect(symbols.count == StateKind.allCases.count - 1)
        #expect(Set(symbols).count == symbols.count)
        #expect(!symbols.contains(""))
    }

    /// Loading is the one exception, and it is the only one: a static glyph standing where a
    /// progress indicator belongs reads as a stalled indicator.
    @Test("loading is the only state without a glyph")
    func loadingDrawsASpinnerInstead() {
        #expect(StateKind.loading.symbolName == nil)
        #expect(StateKind.allCases.filter { $0.symbolName == nil } == [.loading])
    }

    /// `G-7.3`: a semantic colour reports a direction, so only the state the user is being asked to
    /// act on may take one. Nothing here is good news, which is why `positive` appears nowhere.
    @Test("error is the only state in a semantic colour, and none is positive")
    func semanticTintIsReservedForError() {
        #expect(StateKind.error.tint == .negative)
        #expect(StateKind.allCases.filter { $0.tint == .negative } == [.error])
        #expect(!StateKind.allCases.map(\.tint).contains(.positive))
    }

    /// A glyph drawn in a surface colour is a glyph drawn in the colour behind it. The card tests
    /// next door pin the same property from the other side.
    @Test("no state draws itself in a backdrop colour")
    func tintsAreNotBackdrops() {
        let backdrops: Set<ColorToken> = [.background, .surface, .surfaceRaised]
        for kind in StateKind.allCases {
            #expect(!backdrops.contains(kind.tint), "\(kind) is invisible against its own surface")
        }
    }

    /// `FR-1.13.3` exists because "nothing yet" and "not enough to compute from" are different
    /// answers, and rendering the second as the first is what produces a zero or a blank chart.
    /// They are allowed to look alike — they are not allowed to be the same case, and the glyph is
    /// what a reader tells them apart by.
    @Test("empty and insufficient-data are separate states with separate glyphs")
    func emptyAndInsufficientDataAreDistinct() {
        #expect(StateKind.empty != StateKind.insufficientData)
        #expect(StateKind.empty.symbolName != StateKind.insufficientData.symbolName)
        #expect(StateKind.empty.tint == StateKind.insufficientData.tint)
    }
}
