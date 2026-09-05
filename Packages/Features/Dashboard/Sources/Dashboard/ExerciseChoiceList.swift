import DesignSystem
import Foundation
import Localization
import SwiftUI

/// The searchable, sectioned toggle list both exercise pickers draw (`FR-16.5.3`).
///
/// **One view, two callers, and neither of them is on another module's side of `TR-1.3`.** The tile
/// picker (`FR-1.9.1`) and the recent-records `.chosen` list (`FR-16.3.1`) are both `Dashboard`
/// screens, so this is a `Dashboard` type rather than the `DesignSystem` or `ExerciseLibrary`
/// component the task predicted — only ``DesignSystem/SearchField`` had to move down, because the
/// exercise library's header needs one too. Extracting it here is what stops the second screen from
/// growing its own search and its own idea of what "trained" means.
///
/// **The `.chosen` list stays inline under its scope picker**, which is the shape T-16.07 shipped
/// and its argument still holds: a row leading to a chooser that the current scope ignores is a dead
/// end. Sharing the *view* was the part that was owed, not a push.
struct ExerciseChoiceList: View {
    /// What this list is, or `nil` where the screen has already said.
    ///
    /// **A heading rather than one more ``DesignSystem/GroupedSection``**: the sections below are
    /// cards already, and wrapping them in another would draw a surface around a surface. The tile
    /// picker passes nothing — the screen it fills is titled — where `settings.recentRecords`
    /// reveals this list between three other headed sections, and two unlabelled cards there say
    /// nothing about which scope they belong to.
    var title: LocalizedStringResource?

    /// What the user has typed, bound to whichever state holds it.
    @Binding var searchText: String

    /// The sections to draw, already split and ordered.
    let sections: [ExerciseChoiceSection]

    /// Adds or removes one exercise.
    let toggle: (UUID) -> Void

    /// The field, then the sections — or the field, and a sentence saying nothing matched.
    ///
    /// **The field is drawn above the message and stays there**, which is what makes replacing the
    /// rows safe here where it was not for the dashboard's `noEstimates`: what a row carries and
    /// this message does not is a *ticked* exercise and the only control that unticks it, and the
    /// field the message sits under is one tap from bringing every one of them back. A search the
    /// user typed is a cause they can see; the tiles' empty state had neither.
    var body: some View {
        if let title {
            Text(title)
                .font(Typography.sectionHeading.font)
                .foregroundStyle(ColorToken.textPrimary)
        }
        SearchField(text: $searchText, prompt: DashboardStrings.exerciseSearchPrompt)
        if sections.isEmpty {
            EmptyStateView(
                symbolName: "magnifyingglass",
                headline: Text(DashboardStrings.exerciseSearchNoMatchesHeadline),
                message: Text(DashboardStrings.exerciseSearchNoMatchesMessage),
                action: StateAction(Text(DashboardStrings.exerciseSearchClearAction)) {
                    searchText = ""
                }
            )
        } else {
            ForEach(sections) { section in
                GroupedSection(Text(DashboardStrings.exerciseSectionTitle(for: section.kind))) {
                    ForEach(section.choices) { choice in
                        TiledExerciseRow(choice: choice, toggle: toggle)
                    }
                }
            }
        }
    }
}

/// One exercise, whether it is chosen, and when it was last trained.
///
/// **A `Toggle` rather than a tick and a tap target**, so the control announces its own state to
/// VoiceOver (`G-4.2`) instead of leaving it to a glyph.
struct TiledExerciseRow: View {
    /// The exercise and its current membership.
    let choice: TiledExerciseChoice

    /// What flipping it does.
    let toggle: (UUID) -> Void

    /// The locale the date is rendered in (`G-3.4`) — `Date.FormatStyle` otherwise resolves against
    /// the device's own whatever the screen is rendering for.
    @Environment(\.locale) private var locale

    /// The row: the name, the date beneath it where there is one, and the switch.
    ///
    /// **The date is a caption under the name rather than a trailing column**, because the switch
    /// already owns the trailing edge and a third column would leave the name a third of the width
    /// at the largest Dynamic Type size. It is drawn only for a trained exercise; a row in
    /// **Everything else** has no date to show and the section heading already says so, so there is
    /// nothing an em dash there would add.
    var body: some View {
        Toggle(
            isOn: Binding(get: { choice.isTiled }, set: { _ in toggle(choice.exerciseID) })
        ) {
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                Text(verbatim: choice.name)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
                if let lastTrained = choice.lastTrained {
                    Text(
                        DashboardStrings.exerciseLastTrained(
                            lastTrained.formatted(AppFormat.date(locale: locale)))
                    )
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                }
            }
        }
        .tint(ColorToken.brandAccent)
        .frame(minHeight: TouchTarget.standard.points)
    }
}
