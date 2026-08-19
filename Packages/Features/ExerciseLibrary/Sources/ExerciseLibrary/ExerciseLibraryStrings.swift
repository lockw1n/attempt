import Foundation
import PowerliftingCore

/// This module's copy (`G-3.4`), and the only place an exercise-library string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` and binds it to this module's
/// own bundle. The key convention is documented once, in `Localization`.
///
/// **Two middle segments, not one.** `list` is a screen, as the convention asks. `movement` and
/// `equipment` are not: they are the two domain vocabularies, whose labels every screen in this
/// module shows and none of which owns — putting them under `list` would make T-1.11's detail screen
/// read the list's copy. A vocabulary's label is also the one string here that cannot come from the
/// domain: `Movement` is Foundation-free and carries no display name (`NFR-0.2`).
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

    /// The heading when the catalogue itself has nothing in it.
    static let emptyHeadline = resource("exerciselibrary.list.empty.headline")

    /// What to do about an empty catalogue.
    static let emptyMessage = resource("exerciselibrary.list.empty.message")

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
        case .builtIn: resource("exerciselibrary.list.origin.built-in")
        case .custom: resource("exerciselibrary.list.origin.custom")
        }
    }

    /// Every string this module can show, for the test that proves each one resolves.
    ///
    /// The three vocabularies are mapped rather than listed, so a case added to `Movement` or
    /// `Equipment` arrives here without an edit — and arrives at the test, which is the point.
    static var all: [LocalizedStringResource] {
        [
            title, searchPrompt, movementFilter, equipmentFilter, originFilter, filterAll,
            recentlyUsedFilter, recentlyUsedUnavailable, customBadge,
            emptyHeadline, emptyMessage,
            noMatchesHeadline, noMatchesMessage, noMatchesAction,
            errorHeadline, errorMessage,
        ]
            + Movement.allCases.map(label(for:))
            + Equipment.allCases.map(label(for:))
            + ExerciseOrigin.allCases.map(label(for:))
    }

    /// Binds a key to this module's catalogue.
    private static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
