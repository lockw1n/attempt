import DesignSystem
import SwiftUI

/// What the list shows when the search and the filters between them matched nothing
/// (`FR-1.13.1`, `FR-18.1.3`).
///
/// **A view of its own rather than a branch in ``ExerciseListView``**, because it is the one empty
/// state whose content is a decision: which of its two ways out leads, and whether the second is
/// offered at all. A snapshot over a hand-built ``DesignSystem/EmptyStateView`` would picture
/// whatever the fixture chose (`T-16.17`); a snapshot over this pictures what the screen draws.
///
/// The tester who typed *задня дельта в тренажері* met this state carrying **Clear filters** alone,
/// with creation in a toolbar they never looked at (`F-02`, `F-03`). Creating what was typed is the
/// answer to a catalogue gap (`D-18.2`), so it is the action that leads here.
struct ExerciseNoMatchState: View {
    /// The name **Create "‹typed›"** would author, or `nil` where the filters alone caused this and
    /// there is nothing to name.
    let nameToCreate: String?

    /// Opens the create form with that name in it.
    let create: (String) -> Void

    /// Drops the search text and every filter.
    let clearFilters: () -> Void

    /// The state, with one way out or two.
    ///
    /// **The emphasis is the screen's to choose and is chosen here** (`T-16.17`): this placeholder
    /// *is* the screen while it is on it, so whichever action leads takes the filled accent and the
    /// other takes the outline. With nothing typed there is only one action, and it leads.
    var body: some View {
        EmptyStateView(
            symbolName: "magnifyingglass",
            headline: Text(ExerciseLibraryStrings.noMatchesHeadline),
            message: Text(ExerciseLibraryStrings.noMatchesMessage),
            action: nameToCreate.map(createAction) ?? clearAction(emphasis: .primary),
            secondaryAction: nameToCreate == nil ? nil : clearAction(emphasis: .secondary)
        )
    }

    /// **Create "‹typed›"** (`FR-18.1.3`).
    ///
    /// The label truncates in its middle: the quoted part is the lifter's own text, and nothing
    /// bounds its length — at `accessibility3` a wrapped label would push the rest of the state off
    /// the screen, and one cut at the end would lose the closing quote.
    ///
    /// - Parameter name: The name, already trimmed and collapsed by the state.
    /// - Returns: The action.
    private func createAction(_ name: String) -> StateAction {
        StateAction(
            Text(ExerciseLibraryStrings.noMatchesCreate(name)), emphasis: .primary
        ) {
            create(name)
        }
        .truncatingInMiddle()
    }

    /// The way back to the whole catalogue, at whichever weight is left over.
    ///
    /// - Parameter emphasis: `.primary` when it is the only action, `.secondary` beneath Create.
    /// - Returns: The action.
    private func clearAction(emphasis: StateActionEmphasis) -> StateAction {
        StateAction(Text(ExerciseLibraryStrings.noMatchesAction), emphasis: emphasis) {
            clearFilters()
        }
    }
}
