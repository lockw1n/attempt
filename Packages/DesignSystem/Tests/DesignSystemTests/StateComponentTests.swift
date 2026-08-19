import DesignTokens
import SwiftUI
import Testing

@testable import DesignSystem

/// The five placeholders `FR-1.13.1` and `FR-1.13.3` require, held at the layer a test can reach:
/// which token and which catalogue key each state chooses. What they render is T-1.08's snapshot;
/// a wrong choice here is a wrong constant rather than a wrong pixel.
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
    @Test("loading is the only state that draws a spinner, and it is the only one announced")
    func loadingDrawsASpinnerInstead() {
        #expect(StateKind.loading.indicator == .spinner(label: DesignSystemStrings.loadingLabel))
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

    /// The two states whose headline the caller may omit are exactly the two that have something
    /// generic to say. Empty does not: what is missing is the screen's knowledge.
    @Test("only the states this module can name for itself carry a fallback heading")
    func fallbackHeadingsExistWhereTheCallerMayOmitOne() {
        #expect(StateKind.error.defaultHeadline == DesignSystemStrings.errorHeadline)
        #expect(StateKind.offline.defaultHeadline == DesignSystemStrings.offlineHeadline)
        #expect(
            StateKind.insufficientData.defaultHeadline
                == DesignSystemStrings.insufficientDataHeadline)
        #expect(StateKind.empty.defaultHeadline == nil)
        #expect(StateKind.loading.defaultHeadline == nil)
    }

    /// Offline is the only state whose message is not the caller's to write, so it is the only one
    /// that owns one.
    @Test("offline is the only state that owns its message outright")
    func onlyOfflineFixesItsMessage() {
        #expect(StateKind.offline.fixedMessage == DesignSystemStrings.offlineMessage)
        #expect(StateKind.allCases.filter { $0.fixedMessage != nil } == [.offline])
    }
}

/// What each of the five views actually configures. Without this the enum above is a set of
/// constants nothing is proven to be wired to: a view rendering the wrong kind, dropping its
/// fallback heading or never building its retry is invisible to a token test and to a green build.
@MainActor
@Suite("State placeholder wiring")
struct StateViewWiringTests {
    /// The five views each report their own kind and no other. This is the assertion the token
    /// suite above rests on.
    @Test("each view configures its own kind")
    func eachViewChoosesItsKind() {
        #expect(EmptyStateView(headline: Text(verbatim: "h")).scaffold.kind == .empty)
        #expect(LoadingStateView().scaffold.kind == .loading)
        #expect(ErrorStateView(message: Text(verbatim: "m")).scaffold.kind == .error)
        #expect(OfflineStateView().scaffold.kind == .offline)
        #expect(InsufficientDataView(message: Text(verbatim: "m")).scaffold.kind == .insufficientData)
    }

    /// The offline state passes no copy of its own, so if the kind stops supplying it the screen
    /// shows a bare glyph. Both strings are asserted against the catalogue, not against English.
    @Test("the offline state resolves both of its strings from this module")
    func offlineResolvesItsOwnCopy() {
        let scaffold = OfflineStateView().scaffold
        #expect(scaffold.resolvedHeadline == Text(DesignSystemStrings.offlineHeadline))
        #expect(scaffold.resolvedMessage == Text(DesignSystemStrings.offlineMessage))
        // Anchored to a literal too: a resolution that produced nothing on both sides would satisfy
        // an equality between two optionals.
        #expect(scaffold.resolvedMessage != nil)
    }

    /// The caller may omit the heading on the two states that have a generic one, and must get it.
    @Test("an omitted heading falls back to this module's, and a supplied one wins")
    func headingFallsBackAndIsOverridable() {
        let ownHeadline = Text(verbatim: "Squat history unavailable")

        let error = ErrorStateView(message: Text(verbatim: "m")).scaffold
        #expect(error.resolvedHeadline == Text(DesignSystemStrings.errorHeadline))
        #expect(
            ErrorStateView(headline: ownHeadline, message: Text(verbatim: "m"))
                .scaffold.resolvedHeadline == ownHeadline)

        let insufficient = InsufficientDataView(message: Text(verbatim: "m")).scaffold
        #expect(insufficient.resolvedHeadline == Text(DesignSystemStrings.insufficientDataHeadline))
        #expect(
            InsufficientDataView(headline: ownHeadline, message: Text(verbatim: "m"))
                .scaffold.resolvedHeadline == ownHeadline)
    }

    /// `FR-1.13.2`'s next tap, and the retry out of a failure, are the same mechanism: an action is
    /// built when and only when the caller supplied a handler.
    @Test("a retry is built only when the caller supplies one, and it is labelled from this module")
    func retryIsBuiltOnlyWhenOffered() {
        #expect(ErrorStateView(message: Text(verbatim: "m")).scaffold.action == nil)
        #expect(OfflineStateView().scaffold.action == nil)

        let retryLabel = Text(DesignSystemStrings.retry)
        #expect(
            ErrorStateView(message: Text(verbatim: "m"), retry: {}).scaffold.action?.label
                == retryLabel)
        #expect(OfflineStateView(retry: {}).scaffold.action?.label == retryLabel)
    }

    /// The empty state is the one that takes a caller's glyph, and the default has to survive the
    /// caller not passing one.
    @Test("the empty state takes the caller's glyph and falls back to the kind's")
    func emptyStateGlyphIsOverridable() {
        let headline = Text(verbatim: "No exercises yet")
        #expect(EmptyStateView(headline: headline).scaffold.symbolName == nil)
        #expect(EmptyStateView(headline: headline).scaffold.kind.symbolName == "tray")
        #expect(
            EmptyStateView(symbolName: "dumbbell", headline: headline).scaffold.symbolName
                == "dumbbell")
    }

    /// `G-4.2`: the loading state must read as one thing, not two. A spinner with a message beside
    /// it would otherwise announce "Loading" and then the message as separate stops.
    @Test("the spinner speaks only when no message does")
    func spinnerFallsSilentBehindAMessage() {
        #expect(LoadingStateView().scaffold.spinnerAnnouncement == DesignSystemStrings.loadingLabel)
        #expect(
            LoadingStateView(message: Text(verbatim: "Reading Health data"))
                .scaffold.spinnerAnnouncement == nil)
        // Only the spinner is ever announced: every other kind hides its glyph instead.
        for kind in StateKind.allCases where kind != .loading {
            #expect(StateScaffold(kind: kind).spinnerAnnouncement == nil)
        }
    }
}
