import Foundation
import PowerliftingCore

/// `FR-15.1`'s and `FR-16.7`'s copy: the coach's number, when it took effect, and why it moved.
///
/// A file of its own rather than more of ``ExerciseLibraryStrings``, which had reached SwiftLint's
/// length ceiling. Same type, same catalogue, same key convention.
extension ExerciseLibraryStrings {
    /// The section's heading, above the estimate's.
    static let trainingMaxSection = resource("exerciselibrary.detail.training-max.section")

    /// The number's own label, beside it — `G-4.5`'s word, so the number is never told from the
    /// estimate above it by position alone.
    static let trainingMaxValue = resource("exerciselibrary.detail.training-max.value")

    /// `FR-15.1.5`'s indicator where the change carried no note: the day it took effect.
    ///
    /// **The date arrives already rendered**, on ``e1rmProvenance(_:days:)``'s rule: a date
    /// formatted here would be formatted twice.
    ///
    /// - Parameter date: The day it took effect, rendered for the reader.
    /// - Returns: The line under the number.
    static func trainingMaxSince(_ date: String) -> LocalizedStringResource {
        resource("exerciselibrary.detail.training-max.since \(date)")
    }

    /// The same line where the change carried one (`FR-16.7.2`).
    ///
    /// - Parameters:
    ///   - date: The day it took effect, rendered for the reader.
    ///   - note: What the lifter wrote. Data, so it arrives verbatim.
    /// - Returns: The line under the number.
    static func trainingMaxSince(_ date: String, note: String) -> LocalizedStringResource {
        resource("exerciselibrary.detail.training-max.since-note \(date) \(note)")
    }

    /// There is none, in the three words the line has room for (`FR-17.5.1`).
    static let trainingMaxNoneLine = resource("exerciselibrary.detail.training-max.none-line")

    /// What setting one buys — the sentence ``trainingMaxNoneLine`` was shortened from.
    ///
    /// **Read rather than drawn**, on the dashboard's empty tile's rule (`FR-16.5.2`): the line is
    /// short so that it can be one line, and a reader who cannot see the layout is owed the whole
    /// of it (`G-4.2`).
    static let trainingMaxNone = resource("exerciselibrary.detail.training-max.none")

    /// There are changes, but every one of them is dated ahead of today (`FR-17.5.1`).
    ///
    /// **A different sentence from ``trainingMaxNoneLine``**, because it is a different statement:
    /// the exercise *has* a training max the lifter entered, and what it has not got is one in
    /// force yet. Saying "no training max" over a history of three would call the lifter's own
    /// entries nothing.
    ///
    /// **It names no subject, because this line is the only one drawn inside the card**, under a
    /// heading already reading *Training max*. Naming it again ran the line onto a second row at
    /// the default type size beside its command, which is the shape ``trainingMaxNoneLine`` exists
    /// to avoid. The whole sentence survives as the hint.
    static let trainingMaxNotYetLine = resource("exerciselibrary.detail.training-max.not-yet-line")

    /// What the changes under it are waiting for — ``trainingMaxNotYetLine``'s whole sentence, read
    /// rather than drawn for ``trainingMaxNone``'s reason.
    static let trainingMaxNotYet = resource("exerciselibrary.detail.training-max.not-yet")

    /// The training max could not be read — a retry may fix it.
    static let trainingMaxError = resource("exerciselibrary.detail.training-max.error")

    /// The change could not be stored. Nothing moved, so the retry is the same command.
    static let trainingMaxWriteError = resource("exerciselibrary.detail.training-max.write-error")

    /// The line's own command where nothing has ever been entered (`FR-17.5.1`), two words because
    /// it sits inside a sentence.
    ///
    /// **Its VoiceOver label is ``trainingMaxSetAction``**, which is the same command said in full:
    /// "Set one" reads as a fragment out of the line it was written for.
    static let trainingMaxSetOneAction = resource("exerciselibrary.detail.training-max.set-one")

    /// The line's own command where entries exist and none is in force yet (`FR-17.5.1`).
    ///
    /// **Not ``trainingMaxSetOneAction``, and the difference is the lifter's own history.** Offering
    /// to *set one* over a list of numbers they have already set calls those entries nothing —
    /// which is ``trainingMaxNotYetLine``'s argument, applied to the command rather than only to
    /// the sentence. Its VoiceOver label is ``trainingMaxChangeAction``.
    static let trainingMaxChangeOneAction =
        resource("exerciselibrary.detail.training-max.change-one")

    /// The command where there is no number yet, said in full — the card's label until `FR-17.5.1`
    /// made that state a line, and ``trainingMaxSetOneAction``'s label since.
    static let trainingMaxSetAction = resource("exerciselibrary.detail.training-max.set-action")

    /// The command where there is one (`FR-16.7.2`), and ``trainingMaxChangeOneAction``'s label.
    static let trainingMaxChangeAction =
        resource("exerciselibrary.detail.training-max.change-action")

    /// `FR-15.1.4`'s disclosure.
    static let trainingMaxHistory = resource("exerciselibrary.detail.training-max.history")

    /// The disclosure's state, as VoiceOver reads it (`G-4.2`).
    static let trainingMaxHistoryExpanded =
        resource("exerciselibrary.detail.training-max.history.expanded")

    /// See ``trainingMaxHistoryExpanded``.
    static let trainingMaxHistoryCollapsed =
        resource("exerciselibrary.detail.training-max.history.collapsed")

    /// One history row where something was replaced.
    ///
    /// - Parameters:
    ///   - old: What it was, rendered.
    ///   - new: What it became, rendered.
    /// - Returns: The row's reading.
    static func trainingMaxChange(from old: String, to new: String) -> LocalizedStringResource {
        resource("exerciselibrary.detail.training-max.change \(old) \(new)")
    }

    /// The first row for an exercise, which replaced nothing.
    ///
    /// **Not `0 → 140`.** ``RepositoryInterface/TrainingMaxHistoryEntry/oldWeight`` is `nil` there,
    /// and a zero drawn in its place is a number the lifter never had.
    ///
    /// - Parameter new: What it was set to, rendered.
    /// - Returns: The row's reading.
    static func trainingMaxFirst(_ new: String) -> LocalizedStringResource {
        resource("exerciselibrary.detail.training-max.first \(new)")
    }

    /// A history row's date and note — what a change *started on*, rather than
    /// ``trainingMaxSince(_:note:)``'s claim that it is in force.
    ///
    /// - Parameters:
    ///   - date: The day it took effect, rendered for the reader.
    ///   - note: What the lifter wrote. Data, so it arrives verbatim.
    /// - Returns: The row's footnote.
    static func trainingMaxRowNote(_ date: String, note: String) -> LocalizedStringResource {
        resource("exerciselibrary.detail.training-max.row-note \(date) \(note)")
    }

    /// The change sheet's title, and the only place the sheet names its subject (`FR-17.5.2`).
    static let trainingMaxFormTitle = resource("exerciselibrary.detail.training-max.form.title")

    /// The number's field — its section's heading, its prompt and its VoiceOver label.
    ///
    /// **It says what the field is, not what the sheet is** (`FR-17.5.2`). All three of those read
    /// *Training max* under a navigation bar already saying it, which is one word said four times
    /// before anything has been typed.
    static let trainingMaxWeightLabel = resource("exerciselibrary.detail.training-max.form.weight")

    /// The day it takes effect.
    static let trainingMaxDateLabel = resource("exerciselibrary.detail.training-max.form.date")

    /// Why the date is asked for at all.
    static let trainingMaxDateHint = resource("exerciselibrary.detail.training-max.form.date-hint")

    /// The note's field (`FR-16.7.2`).
    static let trainingMaxNoteLabel = resource("exerciselibrary.detail.training-max.form.note")

    /// What the note field suggests — the requirement's own example.
    static let trainingMaxNotePrompt =
        resource("exerciselibrary.detail.training-max.form.note-prompt")

    /// Commits the change.
    static let trainingMaxSaveAction = resource("exerciselibrary.detail.training-max.form.save")

    /// Leaves without writing anything.
    static let trainingMaxCancelAction = resource("exerciselibrary.detail.training-max.form.cancel")

    /// Why the form will not save yet (`FR-1.13.3`).
    ///
    /// - Parameter refusal: What is wrong with what was typed.
    /// - Returns: The sentence under the save command.
    static func trainingMaxRefusal(_ refusal: TrainingMaxDraftRefusal) -> LocalizedStringResource {
        switch refusal {
        case .notAWeight: resource("exerciselibrary.detail.training-max.form.refusal.not-a-weight")
        case .notPositive: resource("exerciselibrary.detail.training-max.form.refusal.not-positive")
        }
    }

    /// The load's unit, which is the user's display preference rather than a constant (`G-3.1`).
    ///
    /// - Parameter unit: The unit the number is entered in.
    /// - Returns: The symbol.
    static func trainingMaxUnitSymbol(for unit: MassUnit) -> LocalizedStringResource {
        switch unit {
        case .kilograms: resource("exerciselibrary.detail.training-max.form.unit.kilograms")
        case .pounds: resource("exerciselibrary.detail.training-max.form.unit.pounds")
        }
    }

    /// Every string this section can show, for the test that proves each one resolves.
    ///
    /// The refusals are mapped rather than listed, so a case added to ``TrainingMaxDraftRefusal``
    /// arrives at the test without an edit.
    static var allTrainingMaxStrings: [LocalizedStringResource] {
        [
            trainingMaxSection, trainingMaxValue, trainingMaxNone, trainingMaxNoneLine,
            trainingMaxNotYet, trainingMaxNotYetLine, trainingMaxError,
            trainingMaxWriteError, trainingMaxSetAction, trainingMaxSetOneAction,
            trainingMaxChangeAction, trainingMaxChangeOneAction,
            trainingMaxHistory, trainingMaxHistoryExpanded, trainingMaxHistoryCollapsed,
            trainingMaxSince("1 May"), trainingMaxSince("1 May", note: "coach"),
            trainingMaxChange(from: "170 kg", to: "180 kg"), trainingMaxFirst("180 kg"),
            trainingMaxRowNote("1 May", note: "coach"),
            trainingMaxFormTitle, trainingMaxWeightLabel, trainingMaxDateLabel,
            trainingMaxDateHint, trainingMaxNoteLabel, trainingMaxNotePrompt,
            trainingMaxSaveAction, trainingMaxCancelAction,
        ] + TrainingMaxDraftRefusal.allCases.map(trainingMaxRefusal)
            + MassUnit.allCases.map(trainingMaxUnitSymbol(for:))
    }
}
