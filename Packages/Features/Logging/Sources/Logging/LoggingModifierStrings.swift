import Foundation
import PowerliftingCore

/// `FR-1.2.8`'s copy — the modifier row, the picker over it and the list editor behind that.
///
/// **An extension in a second file rather than more of ``LoggingStrings``**, which is `file_length`
/// rather than a decomposition: the catalogue accessors grow once per screen and this module already
/// carries three screens' worth. ``LoggingStrings/all`` concatenates ``allModifierStrings``, so the
/// test that proves every key resolves still sees one list.
extension LoggingStrings {
    /// The editor's sixth row — the modifiers applied to the set.
    static let setModifierLabel = resource("logging.session.set.modifier.label")

    /// That the row is optional. One word, on the note field's rule: the picker behind the row
    /// is where the terms themselves are explained, and at `accessibility3` a sentence here pushed
    /// the last two fields off the sheet.
    static let setModifierHint = resource("logging.session.set.modifier.hint")

    /// What the row's control says when nothing is applied.
    static let setModifierNone = resource("logging.session.set.modifier.none")

    /// The picker's title, and the heading over the terms it offers.
    static let setModifierPickerTitle = resource("logging.session.set.modifier.picker.title")

    /// The way out of the picker, back to the form.
    static let setModifierDoneAction = resource("logging.session.set.modifier.done.action")

    /// The way from the picker into the list editor (`FR-1.2.8`'s "configurable").
    static let setModifierManageAction = resource("logging.session.set.modifier.manage.action")

    /// The list editor's title.
    static let setModifierManageTitle = resource("logging.session.set.modifier.manage.title")

    /// What renaming or removing a term does *not* do — the one consequence a user cannot see.
    static let setModifierManageHint = resource("logging.session.set.modifier.manage.hint")

    /// The heading over the nine terms nobody can edit.
    static let setModifierBuiltInSection = resource("logging.session.set.modifier.built-in.section")

    /// The heading over the user's own terms.
    static let setModifierCustomSection = resource("logging.session.set.modifier.custom.section")

    /// What the list editor says where the user has added nothing yet.
    static let setModifierCustomEmpty = resource("logging.session.set.modifier.custom.empty")

    /// The field a new term is typed into.
    static let setModifierAddLabel = resource("logging.session.set.modifier.add.label")

    /// The command beside it.
    static let setModifierAddAction = resource("logging.session.set.modifier.add.action")

    /// Why a typed term was not added — empty, or already on the list.
    static let setModifierAddRefusal = resource("logging.session.set.modifier.add.refusal")

    /// The command that stops offering one of the user's own terms.
    static let setModifierRemoveAction = resource("logging.session.set.modifier.remove.action")

    /// The label on a term a set carries that the list does not offer (`OpenVocabulary`'s case).
    static let setModifierUnlisted = resource("logging.session.set.modifier.unlisted")

    /// Whether a term is applied to the set being edited, as VoiceOver's value on its row.
    ///
    /// - Parameter isApplied: Whether it is applied.
    /// - Returns: The word.
    static func setModifierState(isApplied: Bool) -> LocalizedStringResource {
        isApplied
            ? resource("logging.session.set.modifier.applied")
            : resource("logging.session.set.modifier.not-applied")
    }

    /// One built-in modifier's name, in the user's language (`G-3.4`).
    ///
    /// **A switch over literal keys rather than a key built from
    /// ``PowerliftingCore/SetModifierTerm``'s `rawValue`.** The raw value is the wire format —
    /// renaming a case is a storage migration — and a key interpolated from it would make the
    /// catalogue's keys move with it silently. A term this
    /// version does not recognise has no name here at all: the picker draws its spelling.
    ///
    /// - Parameter term: The built-in term.
    /// - Returns: Its name.
    static func setModifierName(for term: SetModifierTerm) -> LocalizedStringResource {
        switch term {
        case .belt: resource("logging.session.set.modifier.belt")
        case .sleeves: resource("logging.session.set.modifier.sleeves")
        case .wraps: resource("logging.session.set.modifier.wraps")
        case .straps: resource("logging.session.set.modifier.straps")
        case .paused: resource("logging.session.set.modifier.paused")
        case .tempo: resource("logging.session.set.modifier.tempo")
        case .touchAndGo: resource("logging.session.set.modifier.touch-and-go")
        case .deficit: resource("logging.session.set.modifier.deficit")
        case .board: resource("logging.session.set.modifier.board")
        }
    }

    /// Every string this file names, for ``LoggingStrings/all``.
    static var allModifierStrings: [LocalizedStringResource] {
        [
            setModifierLabel, setModifierHint, setModifierNone, setModifierPickerTitle,
            setModifierDoneAction, setModifierManageAction, setModifierManageTitle,
            setModifierManageHint, setModifierBuiltInSection, setModifierCustomSection,
            setModifierCustomEmpty, setModifierAddLabel, setModifierAddAction,
            setModifierAddRefusal, setModifierRemoveAction, setModifierUnlisted,
        ] + SetModifierTerm.allCases.map(setModifierName(for:))
            + [true, false].map(setModifierState(isApplied:))
    }
}
