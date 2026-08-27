import Foundation

/// The bodyweight screen's copy (`G-3.4`), in the same type as the rest of this module's — a second
/// file rather than a second enum, so ``SettingsStrings/all`` stays the module's one list.
extension SettingsStrings {
    /// The screen's own name, which a pushed screen supplies for itself.
    static let bodyweightTitle = resource("settings.bodyweight.title")

    /// The command that opens the form, in the toolbar and in the empty state.
    static let bodyweightAddAction = resource("settings.bodyweight.add.action")

    /// The heading over `FR-1.8.3`'s average — the window ending **today**, which is why the copy
    /// says "current": a row's caption below names a different window and the two disagree.
    static let bodyweightAverageTitle = resource("settings.bodyweight.average.title")

    /// What would make an average showable (`FR-1.13.3`), for the week that holds too few readings.
    static let bodyweightAverageNone = resource("settings.bodyweight.average.none")

    /// The label beside a row's own seven-day figure — the window ending on **that row's** day,
    /// named as such so it is not read as the card's.
    static let bodyweightReadingAverage = resource("settings.bodyweight.reading.average")

    /// The heading over the list itself.
    static let bodyweightHistoryTitle = resource("settings.bodyweight.history.title")

    /// Nothing has ever been weighed.
    static let bodyweightEmptyHeadline = resource("settings.bodyweight.empty.headline")

    /// What the first reading buys.
    static let bodyweightEmptyMessage = resource("settings.bodyweight.empty.message")

    /// The heading over a log that could not be read.
    static let bodyweightErrorHeadline = resource("settings.bodyweight.error.headline")

    /// What failed, in the user's terms.
    static let bodyweightErrorMessage = resource("settings.bodyweight.error.message")

    /// The heading over a reading that could not be written.
    static let bodyweightWriteErrorTitle = resource("settings.bodyweight.write-error.title")

    /// The form's own title.
    static let bodyweightFormTitle = resource("settings.bodyweight.form.title")

    /// The weight field's label.
    static let bodyweightWeightLabel = resource("settings.bodyweight.form.weight.label")

    /// The date picker's label (`FR-1.8.1`).
    static let bodyweightDateLabel = resource("settings.bodyweight.form.date.label")

    /// What the date is for — backdating, said before it is needed.
    static let bodyweightDateHint = resource("settings.bodyweight.form.date.hint")

    /// The command that writes the reading.
    static let bodyweightSaveAction = resource("settings.bodyweight.form.save.action")

    /// Leaving the form without writing.
    static let bodyweightCancelAction = resource("settings.bodyweight.form.cancel.action")

    /// Why the form will not save (`FR-1.13.3`).
    ///
    /// - Parameter refusal: What the draft objects to.
    /// - Returns: The sentence naming the next thing to fix.
    static func bodyweightRefusal(_ refusal: BodyweightDraftRefusal) -> LocalizedStringResource {
        switch refusal {
        case .notAWeight: resource("settings.bodyweight.form.refusal.not-a-weight")
        case .notPositive: resource("settings.bodyweight.form.refusal.not-positive")
        }
    }

    /// The bodyweight screen's keys, for the test that proves each one resolves.
    static var allBodyweightStrings: [LocalizedStringResource] {
        [
            bodyweightTitle, bodyweightAddAction, bodyweightAverageTitle, bodyweightAverageNone,
            bodyweightReadingAverage, bodyweightHistoryTitle, bodyweightEmptyHeadline,
            bodyweightEmptyMessage, bodyweightErrorHeadline, bodyweightErrorMessage,
            bodyweightWriteErrorTitle, bodyweightFormTitle, bodyweightWeightLabel,
            bodyweightDateLabel, bodyweightDateHint, bodyweightSaveAction, bodyweightCancelAction,
        ] + BodyweightDraftRefusal.allCases.map(bodyweightRefusal)
    }
}
