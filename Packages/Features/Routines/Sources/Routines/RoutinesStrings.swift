import Foundation
import PowerliftingCore

/// This module's copy (`G-3.4`), and the only place a routines string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` and binds it to this module's
/// own bundle. The key convention is documented once, in `Localization`.
///
/// **This file is the day and everything under it; `ProgramStrings.swift` is the week.** The seam
/// is the record: a day is a routine row and a week is a program row (`FR-17.10.2`). Single
/// backticks because that file is a second `extension` of this enum rather than a type of its own.
enum RoutinesStrings {
    // MARK: - A day (FR-17.10.1, FR-17.10.4)

    /// *Day 1* — the position, drawn on every day whether or not it has a name.
    ///
    /// - Parameter number: Its place in the week, counting from one.
    /// - Returns: The heading.
    static func dayNumber(_ number: Int) -> LocalizedStringResource {
        resource("routines.day.number \(number)")
    }

    /// What a day added from the foot of the week is called until the lifter renames it.
    ///
    /// - Parameter number: Its place in the week, counting from one.
    /// - Returns: The name.
    static func dayDefaultName(_ number: Int) -> LocalizedStringResource {
        resource("routines.day.default-name \(number)")
    }

    /// What a copy is called. The original's name is the argument and is never looked up — it is
    /// the lifter's own words.
    ///
    /// - Parameter name: The original's name.
    /// - Returns: The copy's.
    static func dayDuplicateName(_ name: String) -> LocalizedStringResource {
        resource("routines.day.duplicate.name \(name)")
    }

    /// A day whose routine has been archived (`FR-15.2.5`), which this screen still draws.
    static let dayArchived = resource("routines.day.archived")

    /// A day whose routine holds no name — a row a store this app did not write can still produce.
    static let dayUnnamed = resource("routines.day.unnamed")

    /// The per-day menu itself, named for the menu rather than for any item in it (`G-4.2`).
    static let dayMenu = resource("routines.day.menu")

    /// Opens the one-field prompt that retitles a day.
    static let dayRename = resource("routines.day.rename")

    /// Copies a day, its exercises and their targets.
    static let dayDuplicate = resource("routines.day.duplicate")

    /// Moves a day one place towards the start of the week.
    static let dayMoveUp = resource("routines.day.up")

    /// Moves a day one place towards the end of the week.
    static let dayMoveDown = resource("routines.day.down")

    /// Takes a day out of the week (`G-1.3`, soft).
    static let dayRemove = resource("routines.day.remove")

    /// The rename prompt's own title.
    static let dayRenameTitle = resource("routines.day.rename.title")

    /// The rename prompt's placeholder.
    static let dayRenamePrompt = resource("routines.day.rename.prompt")

    /// The removal confirmation's title.
    static let dayRemoveTitle = resource("routines.day.remove.title")

    /// What removing a day does and does not touch.
    static let dayRemoveMessage = resource("routines.day.remove.message")

    /// Backs out of either prompt.
    static let cancel = resource("routines.cancel")

    /// The fold, as a VoiceOver value — there is no expanded trait, and `.isSelected` means a
    /// chosen filter everywhere else in this app.
    static let dayExpanded = resource("routines.day.expanded")

    /// See ``dayExpanded``.
    static let dayCollapsed = resource("routines.day.collapsed")

    /// Why a rename changed nothing: the field held no name.
    static let dayNameRequiredMessage = resource("routines.day.name-required.message")

    // MARK: - A day's exercises (FR-15.2.1)

    /// The command that pushes the catalogue as this day's chooser.
    static let exerciseAdd = resource("routines.editor.exercise.add")

    /// The per-exercise menu itself (`G-4.2`).
    static let exerciseMenu = resource("routines.exercise.menu")

    /// Takes an exercise out of the day.
    static let exerciseRemove = resource("routines.editor.exercise.remove")

    /// A slot whose catalogue row could not be read, drawn broken rather than dropped.
    static let exerciseUnnamed = resource("routines.editor.exercise.unnamed")

    /// Moves an exercise one place towards the start of the day.
    static let exerciseMoveUp = resource("routines.editor.move.up")

    /// Moves an exercise one place towards the end of the day.
    static let exerciseMoveDown = resource("routines.editor.move.down")

    /// The heading when a day prescribes nothing yet.
    static let exercisesEmptyHeadline = resource("routines.editor.exercises.empty.headline")

    /// What to do about a day that prescribes nothing.
    static let exercisesEmptyMessage = resource("routines.editor.exercises.empty.message")

    // MARK: - One target group (FR-15.2.1's amendment, FR-15.2.2)

    /// *Target 1*, *Target 2* — a position rather than a count, which is why it takes no plural.
    ///
    /// - Parameter position: Its place in the exercise, counting from one.
    /// - Returns: The heading.
    static func targetGroupHeading(_ position: Int) -> LocalizedStringResource {
        resource("routines.editor.group.heading \(position)")
    }

    /// The multiplication sign between the three fields — `[105] kg × [4] × [4]` (`FR-17.10.1`).
    ///
    /// **A resource rather than a literal**, on `LoggingWeekStrings.weekPlanTarget`'s rule: the
    /// notation is copy, and the one place a translator can decide it does not read that way is the
    /// catalogue.
    static let targetSeparator = resource("routines.target.separator")

    /// The per-target menu itself (`G-4.2`).
    static let targetMenu = resource("routines.target.menu")

    /// The load field's label, which is also its accessibility label where the notation hides it.
    static let targetWeightLabel = resource("routines.editor.group.weight.label")

    /// The load field's placeholder — `FR-15.2.2`'s blank target, said rather than left blank.
    static let targetWeightPrompt = resource("routines.editor.group.weight.prompt")

    /// The repetitions field's label.
    static let targetRepsLabel = resource("routines.editor.group.reps.label")

    /// The sets field's label.
    static let targetSetsLabel = resource("routines.editor.group.sets.label")

    /// Drawn on a group whose weight is blank — a word and not a tint (`G-4.5`).
    static let targetBlank = resource("routines.editor.group.blank")

    /// Adds a second weight/rep/set group to one exercise.
    static let targetAdd = resource("routines.editor.group.add")

    /// Takes one target off an exercise.
    static let targetRemove = resource("routines.editor.group.remove")

    /// Moves a target one place towards the top set.
    static let targetMoveUp = resource("routines.editor.group.up")

    /// Moves a target one place towards the backoff.
    static let targetMoveDown = resource("routines.editor.group.down")

    /// The unit symbol after the load field (`G-3.1`).
    ///
    /// - Parameter unit: The unit loads are entered in.
    /// - Returns: The symbol.
    static func unitSymbol(for unit: MassUnit) -> LocalizedStringResource {
        switch unit {
        case .kilograms: resource("routines.editor.group.unit.kilograms")
        case .pounds: resource("routines.editor.group.unit.pounds")
        }
    }

    /// Every resource this type can produce, for the test that resolves each one against the
    /// catalogue — `ExerciseLibraryStrings`' own suite has the argument for why a list is kept.
    static var allResources: [LocalizedStringResource] {
        [
            dayArchived, dayUnnamed, dayMenu, dayRename, dayDuplicate, dayMoveUp, dayMoveDown,
            dayRemove, dayRenameTitle, dayRenamePrompt, dayRemoveTitle, dayRemoveMessage, cancel,
            dayExpanded, dayCollapsed, dayNameRequiredMessage,
            exerciseAdd, exerciseMenu, exerciseRemove, exerciseUnnamed, exerciseMoveUp,
            exerciseMoveDown, exercisesEmptyHeadline, exercisesEmptyMessage,
            targetSeparator, targetMenu, targetWeightLabel, targetWeightPrompt, targetRepsLabel,
            targetSetsLabel, targetBlank, targetAdd, targetRemove, targetMoveUp, targetMoveDown,
        ]
            + [dayDuplicateName("Push")]
            + [1, 2].map(dayNumber)
            + [1, 2].map(dayDefaultName)
            + [1, 2].map(targetGroupHeading)
            + MassUnit.allCases.map(unitSymbol(for:))
            + allWeekStrings
    }

    /// Binds a key to this module's catalogue.
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
