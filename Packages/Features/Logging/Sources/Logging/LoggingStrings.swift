import Foundation
import PowerliftingCore

/// This module's copy (`G-3.4`), and — with `LoggingModifierStrings.swift`, which is this same type
/// — the only place a logging string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` and binds it to this module's
/// own bundle. The key convention is documented once, in `Localization`.
///
/// The two middle segments are the two screens this task builds: `train` is the tab's root — where a
/// workout is started, resumed or shown as in progress — and `session` is the workout itself. A
/// string that both would show is still written twice, once per screen, because the two are free to
/// diverge and a shared key is what stops them.
enum LoggingStrings {
    // MARK: - Train root (FR-1.2.1, FR-1.2.11, FR-1.13.2)

    /// The heading when nothing is in progress and nothing has been logged into today yet.
    static let trainEmptyHeadline = resource("logging.train.empty.headline")

    /// What to do about it — `FR-1.13.2`'s guidance towards a first workout.
    static let trainEmptyMessage = resource("logging.train.empty.message")

    /// The command that starts a workout (`FR-1.2.1`).
    static let trainStartAction = resource("logging.train.start.action")

    /// The heading over the date control.
    static let trainDateSection = resource("logging.train.date.section")

    /// The date picker's own label — the backdating half of `FR-1.2.1`.
    static let trainDatePicker = resource("logging.train.date.picker")

    /// What the date control is for, where the label alone does not say it.
    static let trainDateHint = resource("logging.train.date.hint")

    /// The heading when a workout is in progress.
    static let trainInProgressSection = resource("logging.train.in-progress.section")

    /// The training day the workout in progress belongs to.
    static let trainInProgressDay = resource("logging.train.in-progress.day")

    /// When the workout in progress was started.
    static let trainInProgressStarted = resource("logging.train.in-progress.started")

    /// The way back into the workout in progress (`FR-1.2.11`).
    static let trainInProgressResume = resource("logging.train.in-progress.resume")

    /// The way into the exercise library from the session surface.
    static let trainLibraryAction = resource("logging.train.library.action")

    /// The heading over `NFR-1.9`'s toggle.
    static let trainScreenWakeSection = resource("logging.train.screen-wake.section")

    /// The toggle itself (`NFR-1.9`).
    static let trainScreenWakeLabel = resource("logging.train.screen-wake.label")

    /// What the toggle does, in the one sentence the label has no room for.
    static let trainScreenWakeHint = resource("logging.train.screen-wake.hint")

    /// The heading when the workouts could not be read.
    static let trainErrorHeadline = resource("logging.train.error.headline")

    /// What the user can understand about that failure — never the diagnostic.
    static let trainErrorMessage = resource("logging.train.error.message")

    /// A start that could not be written — a failed *write*, beside the command that issued it.
    static let trainStartErrorMessage = resource("logging.train.start-error.message")

    // MARK: - The workout in progress (FR-1.2.11, FR-1.2.12)

    /// The screen's navigation title.
    ///
    /// The screen's rather than the app target's, unlike a tab root's: this one is pushed, so there
    /// is no tab whose name it could contradict.
    static let sessionTitle = resource("logging.session.title")

    /// The heading over the workout's own facts.
    static let sessionSummarySection = resource("logging.session.summary.section")

    /// The training day this workout belongs to.
    static let sessionDay = resource("logging.session.day")

    /// When it was started.
    static let sessionStarted = resource("logging.session.started")

    /// The heading when the workout has no exercises in it yet.
    static let sessionEmptyHeadline = resource("logging.session.empty.headline")

    /// What will fill it.
    static let sessionEmptyMessage = resource("logging.session.empty.message")

    /// The command that finishes the workout (`FR-1.2.11`).
    static let sessionFinishAction = resource("logging.session.finish.action")

    /// The command that discards it (`FR-1.2.12`).
    static let sessionDiscardAction = resource("logging.session.discard.action")

    /// The confirmation's question (`FR-1.2.12`).
    static let sessionDiscardConfirmTitle = resource("logging.session.discard.confirm.title")

    /// What discarding costs, said before it is done.
    static let sessionDiscardConfirmMessage = resource("logging.session.discard.confirm.message")

    /// The confirming button.
    static let sessionDiscardConfirmAction = resource("logging.session.discard.confirm.action")

    /// The way out of the confirmation.
    static let sessionDiscardConfirmCancel = resource("logging.session.discard.confirm.cancel")

    /// The heading when the workout could not be read.
    static let sessionErrorHeadline = resource("logging.session.error.headline")

    /// What the user can understand about that failure — never the diagnostic.
    static let sessionErrorMessage = resource("logging.session.error.message")

    /// The heading when the screen is open on a workout that is no longer in progress.
    static let sessionEndedHeadline = resource("logging.session.ended.headline")

    /// Why it is not there — finished, or discarded.
    static let sessionEndedMessage = resource("logging.session.ended.message")

    /// What the user can understand about a write that failed.
    static let sessionWriteErrorMessage = resource("logging.session.write-error.message")

    // MARK: - The workout's exercises (FR-1.2.2, FR-1.2.13)

    /// The heading over the workout's exercises.
    static let sessionExercisesSection = resource("logging.session.exercises.section")

    /// The command that opens the chooser (`FR-1.2.2`).
    static let sessionAddExerciseAction = resource("logging.session.add-exercise.action")

    /// An exercise that has been finished — `FR-1.2.13`'s collapsed card, said in words as well as
    /// by the fold (`G-4.5`).
    static let sessionExerciseCompleted = resource("logging.session.exercise.completed")

    /// How many sets have been logged against one exercise.
    static let sessionExerciseSets = resource("logging.session.exercise.sets")

    /// Something on this screen that is open, as VoiceOver's value for the control that folds it
    /// (`G-4.2`).
    ///
    /// **One pair for both folds, unlike the module's usual rule.** That rule keeps two *screens*
    /// from sharing a string; the exercise card and the warmup group inside it are one screen and
    /// one word, and writing "Expanded" twice would be two entries a translator has to keep
    /// identical for no reason either could diverge for.
    static let sessionExerciseExpanded = resource("logging.session.exercise.expanded")

    /// Something on this screen that is folded. See ``sessionExerciseExpanded``.
    static let sessionExerciseCollapsed = resource("logging.session.exercise.collapsed")

    /// In place of a name, where the entry points at a catalogue row that is not there.
    static let sessionExerciseMissing = resource("logging.session.exercise.missing")

    /// The control that moves an exercise earlier (`FR-1.2.2`). A label, not a title: the button
    /// draws a glyph.
    static let sessionExerciseMoveUp = resource("logging.session.exercise.move-up")

    /// The control that moves an exercise later (`FR-1.2.2`).
    static let sessionExerciseMoveDown = resource("logging.session.exercise.move-down")

    // MARK: - Sets inside one exercise (FR-1.2.3, FR-1.2.5, FR-1.2.6)

    /// A card that is open and has nothing logged against it yet.
    ///
    /// Data rather than one of `FR-1.13.1`'s states: zero sets is a count the same way three is, and
    /// a state placeholder per card would be five of them down a workout.
    static let setListEmpty = resource("logging.session.set.empty")

    /// The command that opens the editor on a blank set (`FR-1.2.3`).
    static let setAddAction = resource("logging.session.set.add.action")

    /// The command that opens it on a copy of the last set — `FR-1.2.6`, and the dominant logging
    /// action.
    static let setRepeatAction = resource("logging.session.set.repeat.action")

    /// The editor's own title.
    static let setEditorTitle = resource("logging.session.set.editor.title")

    /// The same title when the form is open over a set that already exists (`FR-1.2.7`).
    static let setEditorEditTitle = resource("logging.session.set.editor.edit-title")

    /// The load field's label.
    static let setWeightLabel = resource("logging.session.set.weight.label")

    /// The repetitions field's label.
    static let setRepsLabel = resource("logging.session.set.reps.label")

    /// The RPE field's label.
    static let setRPELabel = resource("logging.session.set.rpe.label")

    /// What the RPE field accepts, said where the label has no room for it.
    static let setRPEHint = resource("logging.session.set.rpe.hint")

    /// The per-set note's label (`FR-1.2.3`).
    static let setNotesLabel = resource("logging.session.set.notes.label")

    /// That the note may be left empty.
    static let setNotesHint = resource("logging.session.set.notes.hint")

    /// The command that logs the set.
    static let setConfirmAction = resource("logging.session.set.confirm.action")

    /// The command that confirms an edit (`FR-1.2.7`), where ``setConfirmAction`` logs a new set.
    ///
    /// **Two strings rather than one**: the editor's confirming command is the same button and not
    /// the same sentence — one stores a set that did not exist, the other rewrites one that did, and
    /// a shared word would have to be vague enough to cover both.
    static let setSaveAction = resource("logging.session.set.save.action")

    /// The way out of the editor without logging anything.
    static let setCancelAction = resource("logging.session.set.cancel.action")

    /// What tapping a set's values does (`FR-1.2.7`), as VoiceOver's hint on that control.
    ///
    /// The action rather than the state, for ``setMarkAction(isWarmup:)``'s reason.
    static let setEditAction = resource("logging.session.set.edit.action")

    /// The editor's deletion (`FR-1.2.7`), and the title of the dialogue confirming it.
    static let setDeleteAction = resource("logging.session.set.delete.action")

    /// The question that confirmation asks.
    static let setDeleteConfirmTitle = resource("logging.session.set.delete.confirm.title")

    /// What deleting the set costs, said before it is deleted rather than after.
    static let setDeleteConfirmMessage = resource("logging.session.set.delete.confirm.message")

    /// The confirmation's destructive command.
    static let setDeleteConfirmAction = resource("logging.session.set.delete.confirm.action")

    /// The way out of that confirmation, naming what it keeps rather than saying "cancel".
    static let setDeleteConfirmCancel = resource("logging.session.set.delete.confirm.cancel")

    /// Accessibility label for the load's **+** control (`G-4.2`).
    static let setWeightIncrease = resource("logging.session.set.weight.increase")

    /// Accessibility label for the load's **−** control.
    static let setWeightDecrease = resource("logging.session.set.weight.decrease")

    /// Accessibility label for the repetitions' **+** control.
    static let setRepsIncrease = resource("logging.session.set.reps.increase")

    /// Accessibility label for the repetitions' **−** control.
    static let setRepsDecrease = resource("logging.session.set.reps.decrease")

    /// Why the confirming command is refusing, shown beside it rather than under a field.
    static let setInvalidMessage = resource("logging.session.set.invalid.message")

    /// The unit a load is entered and shown in (`G-3.1`).
    ///
    /// **Written again here rather than shared with `Settings`.** Two modules showing one symbol is
    /// two strings by this module's own rule — and the two surfaces are free to diverge, a picker of
    /// units and a suffix on a number field not being the same context.
    ///
    /// - Parameter unit: The unit to name.
    /// - Returns: Its abbreviated symbol.
    static func setUnitSymbol(for unit: MassUnit) -> LocalizedStringResource {
        switch unit {
        case .kilograms: resource("logging.session.set.unit.kilograms")
        case .pounds: resource("logging.session.set.unit.pounds")
        }
    }

    /// A set's place in its exercise, as VoiceOver's label for the bare numeral the row draws
    /// (`G-4.2`).
    ///
    /// - Parameter position: The set's one-based position.
    /// - Returns: The sentence.
    static func setPosition(_ position: Int) -> LocalizedStringResource {
        resource("logging.session.set.position \(position)")
    }

    /// A set's repetitions, as VoiceOver's label for the numeral after the multiplication sign,
    /// which is decorative and hidden.
    ///
    /// **A label beside a number rather than a plural**, for ``sessionExerciseSets``' reason.
    ///
    /// - Parameter reps: How many repetitions.
    /// - Returns: The phrase.
    static func setReps(_ reps: Int) -> LocalizedStringResource {
        resource("logging.session.set.reps \(reps)")
    }

    /// The badge a warmup row leads with — `FR-1.2.14`'s `W1`, `W2`.
    ///
    /// **A string rather than a `W` in front of a numeral** (`G-3.4`): the prefix is a word in the
    /// user's language, not punctuation, and a language that does not spell it with a Latin `W` has
    /// nowhere else to say so.
    ///
    /// **The number arrives already rendered**, for ``setRPE(_:)``'s reason and one this call makes
    /// sharper: the working badge beside this one is drawn with `AppFormat` against the view's
    /// locale, so a numeral formatted here instead would be the one number on the row not going
    /// through the same style.
    ///
    /// - Parameter number: The warmup's one-based place among the warmups, already rendered.
    /// - Returns: The badge.
    static func setWarmupNumber(_ number: String) -> LocalizedStringResource {
        resource("logging.session.set.warmup.number \(number)")
    }

    /// The same warmup's place, as VoiceOver's label for that badge (`G-4.2`).
    ///
    /// Never the badge itself: `W1` read aloud is a letter and a digit rather than a warmup.
    ///
    /// - Parameter number: The warmup's one-based place among the warmups.
    /// - Returns: The sentence.
    static func setWarmupPosition(_ number: Int) -> LocalizedStringResource {
        resource("logging.session.set.warmup.position \(number)")
    }

    /// What tapping a set's badge does (`FR-1.2.4`), as VoiceOver's hint on it.
    ///
    /// **The action, not the state**: a hint on a warmup says it can be made a working set, which is
    /// the opposite instruction to the one on the row beside it.
    ///
    /// - Parameter isWarmup: Whether the set is currently a warmup.
    /// - Returns: What a tap would do to it.
    static func setMarkAction(isWarmup: Bool) -> LocalizedStringResource {
        isWarmup
            ? resource("logging.session.set.mark-working")
            : resource("logging.session.set.mark-warmup")
    }

    /// Whether a set was completed or failed (`FR-1.2.5`), as VoiceOver's label for the glyph that
    /// says it.
    ///
    /// **The word the glyph stands for**, which is what keeps the outcome off the tint alone
    /// (`G-4.5`): the row draws a check or a cross, and this is the same fact in a sentence.
    ///
    /// - Parameter isCompleted: Whether the set was completed.
    /// - Returns: The outcome, as a word.
    static func setOutcome(isCompleted: Bool) -> LocalizedStringResource {
        isCompleted
            ? resource("logging.session.set.outcome.completed")
            : resource("logging.session.set.outcome.failed")
    }

    /// What tapping that glyph does (`FR-1.2.5`), as VoiceOver's hint on it.
    ///
    /// The action rather than the state, for ``setMarkAction(isWarmup:)``'s reason.
    ///
    /// - Parameter isCompleted: Whether the set is currently completed.
    /// - Returns: What a tap would do to it.
    static func setOutcomeAction(isCompleted: Bool) -> LocalizedStringResource {
        isCompleted
            ? resource("logging.session.set.mark-failed")
            : resource("logging.session.set.mark-completed")
    }

    /// The heading over `FR-1.2.14`'s collapsible warmup group.
    ///
    /// A label beside a numeral, for ``sessionExerciseSets``' reason.
    static let setWarmupSection = resource("logging.session.set.warmup.section")

    /// The set editor's fifth row — whether the set being logged is a warmup (`FR-1.2.4`).
    static let setWarmupLabel = resource("logging.session.set.warmup.label")

    /// What that choice costs, in the one sentence the label has no room for.
    static let setWarmupHint = resource("logging.session.set.warmup.hint")

    /// A logged set's rating, label and value together.
    ///
    /// The value arrives already rendered, so the number is the locale's rather than this call's.
    ///
    /// - Parameter rating: The rating, formatted.
    /// - Returns: The phrase.
    static func setRPE(_ rating: String) -> LocalizedStringResource {
        resource("logging.session.set.rpe \(rating)")
    }

    /// The heading when the workout's exercises could not be read.
    static let sessionExercisesErrorHeadline = resource("logging.session.exercises.error.headline")

    /// What the user can understand about that failure — never the diagnostic.
    static let sessionExercisesErrorMessage = resource("logging.session.exercises.error.message")

    /// A failed *write* against the exercises, beside the cards it did not cost.
    static let sessionExercisesWriteErrorMessage = resource(
        "logging.session.exercises.write-error.message")

    /// How far through the workout the user is (`FR-1.2.13`).
    ///
    /// **The only string here with a value in it**, so the two numbers are ordered by the
    /// translation rather than by this call — a language that says "of six, three are done" moves
    /// them, and positional arguments in the catalogue are what let it.
    ///
    /// **Its entry lives in `Localizable.stringsdict`, not in `Localizable.strings`**, because the
    /// noun agrees with the *total*: a workout with one exercise in it reads "1 of 1 exercise", and
    /// a language with more than two plural categories needs the catalogue to pick between them
    /// rather than this call. It is the first such string in the app; the convention is in
    /// `Localization`.
    ///
    /// - Parameters:
    ///   - completed: How many exercises are finished.
    ///   - total: How many there are.
    /// - Returns: The sentence.
    static func sessionProgress(completed: Int, total: Int) -> LocalizedStringResource {
        resource("logging.session.progress \(completed) \(total)")
    }

    /// Every string this module can show, for the test that proves each one resolves.
    static var all: [LocalizedStringResource] {
        [
            trainEmptyHeadline, trainEmptyMessage, trainStartAction, trainDateSection,
            trainDatePicker, trainDateHint, trainInProgressSection, trainInProgressDay,
            trainInProgressStarted, trainInProgressResume, trainLibraryAction,
            trainScreenWakeSection, trainScreenWakeLabel, trainScreenWakeHint, trainErrorHeadline,
            trainErrorMessage, trainStartErrorMessage, sessionTitle, sessionSummarySection,
            sessionDay, sessionStarted, sessionEmptyHeadline, sessionEmptyMessage,
            sessionFinishAction, sessionDiscardAction, sessionDiscardConfirmTitle,
            sessionDiscardConfirmMessage, sessionDiscardConfirmAction, sessionDiscardConfirmCancel,
            sessionErrorHeadline, sessionErrorMessage, sessionEndedHeadline, sessionEndedMessage,
            sessionWriteErrorMessage, sessionExercisesSection, sessionAddExerciseAction,
            sessionExerciseCompleted, sessionExerciseSets, sessionExerciseMissing,
            sessionExerciseExpanded, sessionExerciseCollapsed,
            sessionExerciseMoveUp, sessionExerciseMoveDown, sessionExercisesErrorHeadline,
            sessionExercisesErrorMessage, sessionExercisesWriteErrorMessage,
            sessionProgress(completed: 0, total: 0), sessionProgress(completed: 1, total: 1),
            setListEmpty, setAddAction, setRepeatAction, setEditorTitle, setWeightLabel,
            setRepsLabel, setRPELabel, setRPEHint, setNotesLabel, setNotesHint, setConfirmAction,
            setCancelAction, setWeightIncrease, setWeightDecrease, setRepsIncrease, setRepsDecrease,
            setInvalidMessage, setPosition(1), setReps(5), setRPE(""),
            setEditorEditTitle, setSaveAction, setEditAction, setDeleteAction,
            setDeleteConfirmTitle, setDeleteConfirmMessage, setDeleteConfirmAction,
            setDeleteConfirmCancel,
            setWarmupNumber("1"), setWarmupPosition(1), setWarmupSection, setWarmupLabel,
            setWarmupHint,
        ] + allModifierStrings + MassUnit.allCases.map(setUnitSymbol(for:))
            + [true, false].map(setMarkAction(isWarmup:))
            + [true, false].map(setOutcome(isCompleted:))
            + [true, false].map(setOutcomeAction(isCompleted:))
    }

    /// Binds a key to this module's catalogue.
    ///
    /// Internal rather than file-private because `LoggingModifierStrings.swift` is the same type in
    /// a second file — see that file for why there is one.
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
