import Foundation
import PowerliftingCore

/// This module's copy (`G-3.4`), and the only place an exercise-library string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` and binds it to this module's
/// own bundle. The key convention is documented once, in `Localization`.
///
/// **Two middle segments, not one.** `list` and `detail` are screens, as the convention asks.
/// `movement`, `equipment`, `laterality`, `bar-type` and `origin` are not: they are the vocabularies
/// both screens show and neither owns, so they sit one level up. A vocabulary's label is also the
/// one string here that cannot come from the domain — `Movement` is Foundation-free and carries no
/// display name (`NFR-0.2`) — and `ExerciseOrigin`, which is this module's own, is spelled the same
/// way for the same reason.
enum ExerciseLibraryStrings {
    /// The screen's own navigation title.
    ///
    /// The screen's rather than the app target's, unlike a tab root's: this one is pushed, so there
    /// is no tab whose name it could contradict.
    static let title = resource("exerciselibrary.list.title")

    /// The search field's prompt (`FR-1.1.1`).
    static let searchPrompt = resource("exerciselibrary.list.search.prompt")

    /// The movement filter row's label.
    static let movementFilter = resource("exerciselibrary.list.filter.movement")

    /// The equipment filter row's label.
    static let equipmentFilter = resource("exerciselibrary.list.filter.equipment")

    /// The custom/built-in filter row's label.
    static let originFilter = resource("exerciselibrary.list.filter.origin")

    /// The unset position of every filter row — "no narrowing", not "everything selected".
    static let filterAll = resource("exerciselibrary.list.filter.all")

    /// The recency filter, shown disabled until logging lands.
    static let recentlyUsedFilter = resource("exerciselibrary.list.filter.recently-used")

    /// Why the recency filter cannot be used yet. A sentence for the user, not a task reference.
    static let recentlyUsedUnavailable = resource("exerciselibrary.list.filter.recently-used.hint")

    /// The badge on a row the user authored (`FR-1.1.3`).
    static let customBadge = resource("exerciselibrary.list.row.custom")

    /// The control that widens the list to archived exercises (`FR-1.1.5`).
    ///
    /// A `list.filter.*` key because it sits in the filter bar, and not a filter — see
    /// ``ExerciseListState/showsArchived``.
    static let showArchivedFilter = resource("exerciselibrary.list.filter.archived")

    /// The badge on an archived row, once one is shown. The list's own, not the detail screen's:
    /// the key convention is by screen, and the two are free to diverge.
    static let archivedBadge = resource("exerciselibrary.list.row.archived")

    /// The heading when the catalogue itself has nothing in it.
    static let emptyHeadline = resource("exerciselibrary.list.empty.headline")

    /// What to do about an empty catalogue.
    static let emptyMessage = resource("exerciselibrary.list.empty.message")

    /// The heading when every exercise there is has been archived.
    static let archivedOnlyHeadline = resource("exerciselibrary.list.archived-only.headline")

    /// What to do about a catalogue that is entirely archived.
    static let archivedOnlyMessage = resource("exerciselibrary.list.archived-only.message")

    /// The heading when the search and filters matched nothing.
    static let noMatchesHeadline = resource("exerciselibrary.list.no-matches.headline")

    /// What to do about a search that matched nothing.
    static let noMatchesMessage = resource("exerciselibrary.list.no-matches.message")

    /// The way back out of a search that matched nothing.
    static let noMatchesAction = resource("exerciselibrary.list.no-matches.action")

    /// The heading when the catalogue could not be read.
    static let errorHeadline = resource("exerciselibrary.list.error.headline")

    /// What the user can understand about a failed read — never the diagnostic.
    static let errorMessage = resource("exerciselibrary.list.error.message")

    // MARK: - Exercise detail (FR-1.1.6, FR-1.1.7)

    /// The heading over the exercise's own fields.
    static let detailSection = resource("exerciselibrary.detail.section.details")

    /// The movement field's label.
    static let detailMovement = resource("exerciselibrary.detail.field.movement")

    /// The equipment field's label.
    static let detailEquipment = resource("exerciselibrary.detail.field.equipment")

    /// The bar field's label.
    static let detailBar = resource("exerciselibrary.detail.field.bar")

    /// The laterality field's label.
    static let detailLaterality = resource("exerciselibrary.detail.field.laterality")

    /// The custom/built-in field's label.
    static let detailOrigin = resource("exerciselibrary.detail.field.origin")

    /// The badge on an archived exercise (`FR-1.1.5`).
    static let detailArchivedBadge = resource("exerciselibrary.detail.badge.archived")

    /// The heading over the notes editor (`FR-1.1.6`).
    static let notesSection = resource("exerciselibrary.detail.section.notes")

    /// What the empty notes field invites.
    static let notesPrompt = resource("exerciselibrary.detail.notes.prompt")

    /// Commits the edited notes.
    static let notesSave = resource("exerciselibrary.detail.notes.save")

    /// Puts the stored notes back.
    static let notesDiscard = resource("exerciselibrary.detail.notes.discard")

    /// What the user can understand about a failed write — never the diagnostic.
    static let notesError = resource("exerciselibrary.detail.notes.error")

    /// The heading over the archive control (`FR-1.1.5`).
    static let archiveSection = resource("exerciselibrary.detail.section.archive")

    /// What archiving does, shown above the control on a live exercise.
    static let archiveExplanation = resource("exerciselibrary.detail.archive.explanation")

    /// Archives the exercise.
    static let archiveAction = resource("exerciselibrary.detail.archive.action")

    /// Why this exercise is not in the list, shown above the control on an archived one.
    static let unarchiveExplanation = resource("exerciselibrary.detail.unarchive.explanation")

    /// Brings the exercise back.
    static let unarchiveAction = resource("exerciselibrary.detail.unarchive.action")

    /// What the user can understand about an archive write that failed — never the diagnostic.
    static let archiveError = resource("exerciselibrary.detail.archive.error")

    /// The heading over the variation relationships (`FR-1.1.7`).
    static let variationsSection = resource("exerciselibrary.detail.section.variations")

    /// Precedes the parent exercise's name.
    static let variationOf = resource("exerciselibrary.detail.variations.parent")

    /// The heading over this exercise's logged history.
    static let historySection = resource("exerciselibrary.detail.section.history")

    /// Why there is no history yet, and what would produce some.
    static let historyNone = resource("exerciselibrary.detail.history.none")

    /// The heading over this exercise's personal records.
    static let recordsSection = resource("exerciselibrary.detail.section.records")

    /// Why there are no records yet, and what would produce some.
    static let recordsNone = resource("exerciselibrary.detail.records.none")

    /// The heading over the current estimated one-rep max.
    static let e1rmSection = resource("exerciselibrary.detail.section.e1rm")

    /// Why there is no estimate yet, and what would produce one.
    static let e1rmNone = resource("exerciselibrary.detail.e1rm.none")

    /// The heading when the exercise could not be read.
    static let detailErrorHeadline = resource("exerciselibrary.detail.error.headline")

    /// What the user can understand about a failed read.
    static let detailErrorMessage = resource("exerciselibrary.detail.error.message")

    /// The heading when the identifier resolves to nothing.
    static let detailMissingHeadline = resource("exerciselibrary.detail.missing.headline")

    /// What a route naming an exercise that has gone means for the user.
    static let detailMissingMessage = resource("exerciselibrary.detail.missing.message")

    // MARK: - Create / edit form (FR-1.1.3, FR-1.1.4)

    /// The command that opens the create form, on the list's toolbar and in its empty state.
    static let createAction = resource("exerciselibrary.list.create")

    /// The command that opens the edit form, on the detail screen's toolbar.
    static let editAction = resource("exerciselibrary.detail.edit")

    /// The create form's own navigation title.
    static let formCreateTitle = resource("exerciselibrary.form.create.title")

    /// The edit form's own navigation title.
    static let formEditTitle = resource("exerciselibrary.form.edit.title")

    /// The heading over the exercise's own fields.
    static let formSection = resource("exerciselibrary.form.section.details")

    /// The name field's label.
    static let formName = resource("exerciselibrary.form.field.name")

    /// What the empty name field invites.
    static let formNamePrompt = resource("exerciselibrary.form.name.prompt")

    /// Why the save command is unavailable — the one field that blocks it.
    static let formNameRequired = resource("exerciselibrary.form.name.required")

    /// The movement chips' label.
    static let formMovement = resource("exerciselibrary.form.field.movement")

    /// The equipment chips' label.
    static let formEquipment = resource("exerciselibrary.form.field.equipment")

    /// The bar chips' label.
    static let formBar = resource("exerciselibrary.form.field.bar")

    /// The laterality chips' label.
    static let formLaterality = resource("exerciselibrary.form.field.laterality")

    /// Whose the fields below the name are, on a built-in exercise whose fields are not the user's.
    static let formCatalogueOwned = resource("exerciselibrary.form.catalogue-owned")

    /// The heading over the parent picker (`FR-1.1.7`), and the label of the read-only row that
    /// replaces it where the catalogue owns the parent.
    static let formParentSection = resource("exerciselibrary.form.section.parent")

    /// The parent picker's unset position — a root exercise, not a missing answer.
    static let formParentNone = resource("exerciselibrary.form.parent.none")

    /// Widens the parent picker past the movement the form has selected.
    static let formParentEveryMovement = resource("exerciselibrary.form.parent.every-movement")

    /// Shown when the picker has nothing to offer, and what would give it something.
    static let formParentEmpty = resource("exerciselibrary.form.parent.empty")

    /// Commits the form.
    static let formSave = resource("exerciselibrary.form.save")

    /// The heading when the exercise being edited could not be read.
    static let formErrorHeadline = resource("exerciselibrary.form.error.headline")

    /// What the user can understand about a failed read — never the diagnostic.
    static let formErrorMessage = resource("exerciselibrary.form.error.message")

    /// The heading when the identifier being edited resolves to nothing.
    static let formMissingHeadline = resource("exerciselibrary.form.missing.headline")

    /// What an edit route naming an exercise that has gone means for the user.
    static let formMissingMessage = resource("exerciselibrary.form.missing.message")

    /// What the user can understand about a failed save — never the diagnostic.
    static let formWriteError = resource("exerciselibrary.form.write-error")

    /// A movement's display name, used as a group heading and as a filter label.
    ///
    /// - Parameter movement: The movement to label.
    /// - Returns: Its name.
    static func label(for movement: Movement) -> LocalizedStringResource {
        switch movement {
        case .squat: resource("exerciselibrary.movement.squat")
        case .bench: resource("exerciselibrary.movement.bench")
        case .deadlift: resource("exerciselibrary.movement.deadlift")
        case .overheadPress: resource("exerciselibrary.movement.overhead-press")
        case .row: resource("exerciselibrary.movement.row")
        case .other: resource("exerciselibrary.movement.other")
        }
    }

    /// An equipment's display name, used as a filter label and as a row's subtitle.
    ///
    /// - Parameter equipment: The equipment to label.
    /// - Returns: Its name.
    static func label(for equipment: Equipment) -> LocalizedStringResource {
        switch equipment {
        case .barbell: resource("exerciselibrary.equipment.barbell")
        case .dumbbell: resource("exerciselibrary.equipment.dumbbell")
        case .kettlebell: resource("exerciselibrary.equipment.kettlebell")
        case .machine: resource("exerciselibrary.equipment.machine")
        case .cable: resource("exerciselibrary.equipment.cable")
        case .smithMachine: resource("exerciselibrary.equipment.smith-machine")
        case .bodyweight: resource("exerciselibrary.equipment.bodyweight")
        case .band: resource("exerciselibrary.equipment.band")
        case .other: resource("exerciselibrary.equipment.other")
        }
    }

    /// An origin's display name, for the custom/built-in filter.
    ///
    /// - Parameter origin: The side of the split to label.
    /// - Returns: Its name.
    static func label(for origin: ExerciseOrigin) -> LocalizedStringResource {
        switch origin {
        case .builtIn: resource("exerciselibrary.origin.built-in")
        case .custom: resource("exerciselibrary.origin.custom")
        }
    }

    /// How many sides a rep works, as a word (`TR-0.3.1`).
    ///
    /// - Parameter laterality: The value to label.
    /// - Returns: Its name.
    static func label(for laterality: Laterality) -> LocalizedStringResource {
        switch laterality {
        case .bilateral: resource("exerciselibrary.laterality.bilateral")
        case .unilateral: resource("exerciselibrary.laterality.unilateral")
        case .alternating: resource("exerciselibrary.laterality.alternating")
        }
    }

    /// A bar's display name.
    ///
    /// - Parameter barType: The bar to label.
    /// - Returns: Its name.
    static func label(for barType: BarType) -> LocalizedStringResource {
        switch barType {
        case .standard: resource("exerciselibrary.bar-type.standard")
        case .ezCurl: resource("exerciselibrary.bar-type.ez-curl")
        case .trap: resource("exerciselibrary.bar-type.trap")
        case .safetySquat: resource("exerciselibrary.bar-type.safety-squat")
        case .cambered: resource("exerciselibrary.bar-type.cambered")
        case .swiss: resource("exerciselibrary.bar-type.swiss")
        case .noBar: resource("exerciselibrary.bar-type.no-bar")
        case .other: resource("exerciselibrary.bar-type.other")
        }
    }

    /// Every string this module can show, for the test that proves each one resolves.
    ///
    /// The five vocabularies are mapped rather than listed, so a case added to `Movement`,
    /// `Equipment`, `Laterality` or `BarType` arrives here without an edit — and arrives at the
    /// test, which is the point.
    static var all: [LocalizedStringResource] {
        [
            title, searchPrompt, movementFilter, equipmentFilter, originFilter, filterAll,
            recentlyUsedFilter, recentlyUsedUnavailable, customBadge,
            showArchivedFilter, archivedBadge,
            emptyHeadline, emptyMessage,
            archivedOnlyHeadline, archivedOnlyMessage,
            noMatchesHeadline, noMatchesMessage, noMatchesAction,
            errorHeadline, errorMessage,
            detailSection, detailMovement, detailEquipment, detailBar, detailLaterality,
            detailOrigin, detailArchivedBadge,
            notesSection, notesPrompt, notesSave, notesDiscard, notesError,
            archiveSection, archiveExplanation, archiveAction,
            unarchiveExplanation, unarchiveAction, archiveError,
            variationsSection, variationOf,
            historySection, historyNone, recordsSection, recordsNone, e1rmSection, e1rmNone,
            detailErrorHeadline, detailErrorMessage, detailMissingHeadline, detailMissingMessage,
            createAction, editAction, formCreateTitle, formEditTitle, formSection,
            formName, formNamePrompt, formNameRequired, formMovement, formEquipment, formBar,
            formLaterality, formCatalogueOwned, formParentSection, formParentNone,
            formParentEveryMovement,
            formParentEmpty, formSave, formErrorHeadline, formErrorMessage, formMissingHeadline,
            formMissingMessage, formWriteError,
        ]
            + Movement.allCases.map(label(for:))
            + Equipment.allCases.map(label(for:))
            + ExerciseOrigin.allCases.map(label(for:))
            + Laterality.allCases.map(label(for:))
            + BarType.allCases.map(label(for:))
    }

    /// Binds a key to this module's catalogue.
    private static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
