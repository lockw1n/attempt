import Foundation
import PowerliftingCore

/// The set modifiers this app offers to be picked from — `FR-1.2.8`'s **configurable** list: the
/// nine built-in terms, plus whatever the user has added.
///
/// **A vocabulary, not a set of flags.** What a set carries is a `SetModifier`, which preserves any
/// spelling; this type only decides what is *offered*. The two are deliberately separate, and the
/// consequence is the one thing a caller has to know: **renaming or removing a term here never
/// touches a logged set.** `G-1.6` forbids rewriting logged data, so a set that recorded `chains`
/// keeps recording `chains` after the term is renamed — the spelling simply stops being recognised,
/// which is the case ``OpenVocabulary`` exists for and ``offered(with:)`` is how the picker still
/// shows it.
///
/// **The nine built-ins cannot be renamed or removed.** They are what ``SetModifierTerm`` decodes,
/// so a list that could delete one would leave stored sets naming a term the app declines to offer
/// while still recognising it — two answers to one question.
///
/// **Its storage is a stub, deliberately, and `UserDefaults` rather than the settings row**, on
/// ``ScreenWakePreference``'s argument: `FR-1.10`'s preferences live on
/// ``RepositoryInterface/UserSettings``, schema v1 is frozen, and adding a column is a migration
/// rather than a screen's business. T-1.60 takes this key's value with it.
@Observable
public final class SetModifierVocabulary {
    /// The terms the user added, in the order they were added.
    ///
    /// Raw spellings rather than `SetModifier`s, because that is what `UserDefaults` stores and the
    /// wrapper adds nothing to a list that is by definition unrecognised.
    public private(set) var custom: [String]

    @ObservationIgnored private let defaults: UserDefaults

    /// Reads the stored list, or an empty one where nothing has been stored.
    ///
    /// - Parameter defaults: Where the list is kept. The standard suite in the app; a throwaway
    ///   suite in a test, which is what keeps one test's terms out of the next one's.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        custom = defaults.array(forKey: Self.key) as? [String] ?? []
    }

    /// The nine `FR-1.2.8` names, in ``SetModifierTerm``'s declaration order.
    ///
    /// Declaration order rather than alphabetical: the enum groups the supports together and the
    /// execution styles after them, and a picker sorted by an English spelling would be sorted by
    /// nothing at all in another language (`G-3.4`).
    public static let builtIn: [SetModifier] = SetModifierTerm.allCases.map(SetModifier.init)

    /// Everything the picker offers: the nine, then the user's own.
    public var terms: [SetModifier] {
        Self.builtIn + custom.map(SetModifier.init(rawValue:))
    }

    /// ``terms``, plus any spelling `applied` carries that this list does not offer.
    ///
    /// **The half that keeps a modifier from vanishing.** A set can carry a term written by a newer
    /// version, or one whose entry has since been removed from the list; offered only the terms it
    /// knows, the picker would draw such a set as though the modifier were not there and the next
    /// confirm would drop it. Appended rather than merged in, so an unrecognised spelling reads as
    /// what it is.
    ///
    /// - Parameter applied: What the set being edited carries.
    /// - Returns: Every term to draw a row for, offered ones first.
    public func offered(with applied: [SetModifier]) -> [SetModifier] {
        let known = terms
        let spellings = Set(known.map(\.rawValue))
        var extra: [SetModifier] = []
        for modifier in applied where !spellings.contains(modifier.rawValue) {
            if !extra.contains(modifier) { extra.append(modifier) }
        }
        return known + extra
    }

    /// Adds a term to the list (`FR-1.2.8`).
    ///
    /// **Trimmed of surrounding whitespace and refused when empty or already offered**, which is the
    /// one place anything here normalises anything and is why `SetModifier` does not: a spelling
    /// typed into a text field has a trailing space by accident, where a spelling that arrived from
    /// storage has one on purpose.
    ///
    /// **The duplicate check is against both the drawn name and the stored spelling,
    /// case-insensitively** — see ``isDuplicate(_:excluding:)``. Stored verbatim all the same: what
    /// is refused is a second row the user could not tell from the first, not a spelling.
    ///
    /// - Parameter spelling: What the user typed.
    /// - Returns: The term, or `nil` where it was empty or duplicated.
    @discardableResult
    public func add(_ spelling: String) -> SetModifier? {
        let trimmed = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isDuplicate(trimmed) else { return nil }
        custom.append(trimmed)
        persist()
        return SetModifier(rawValue: trimmed)
    }

    /// Whether a term reading `spelling` — or *stored* as it — is already on the list.
    ///
    /// **Both names are compared, and without regard to case.** The drawn one is the software
    /// keyboard rather than a preference: it capitalises the first word by default, so a user typing
    /// `belt` gets `Belt` — a term the app would neither recognise nor refuse, drawn in the picker as
    /// a second row indistinguishable from the built-in one. The stored one is the half a display
    /// name cannot cover: `touchAndGo` reads as *Touch and go*, so a spelling check against the drawn
    /// name alone admits the raw one and the list then holds two terms with one ``SetModifier`` —
    /// which is a repeated identity in the picker's rows and a built-in that ``rename(_:to:)`` will
    /// edit. Localisation makes that the ordinary case rather than the exotic one: outside English
    /// no built-in's drawn name is its spelling (`G-3.4`).
    ///
    /// - Parameters:
    ///   - spelling: The trimmed spelling.
    ///   - term: A term to ignore — the one being renamed, so that correcting its own capitalisation
    ///     is not refused as a duplicate of itself.
    /// - Returns: Whether something already offered reads the same, or is spelled the same.
    private func isDuplicate(_ spelling: String, excluding term: SetModifier? = nil) -> Bool {
        terms.contains { offered in
            guard offered != term else { return false }
            return offered.displayName.caseInsensitiveCompare(spelling) == .orderedSame
                || offered.rawValue.caseInsensitiveCompare(spelling) == .orderedSame
        }
    }

    /// Renames one of the user's own terms (`FR-1.2.8`).
    ///
    /// **Logged sets keep the old spelling** — see this type's note. Renamed in place rather than
    /// removed and re-added, so the list does not reorder under the thumb that edited it.
    ///
    /// - Parameters:
    ///   - modifier: The term to rename. A built-in one is refused.
    ///   - spelling: What it becomes, trimmed and refused on ``add(_:)``'s rules — except against
    ///     itself, so correcting a term's own capitalisation goes through.
    /// - Returns: Whether anything changed.
    @discardableResult
    public func rename(_ modifier: SetModifier, to spelling: String) -> Bool {
        let trimmed = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let position = custom.firstIndex(of: modifier.rawValue), !trimmed.isEmpty,
            trimmed != modifier.rawValue, !isDuplicate(trimmed, excluding: modifier)
        else {
            return false
        }
        custom[position] = trimmed
        persist()
        return true
    }

    /// Removes one of the user's own terms from the list (`FR-1.2.8`).
    ///
    /// **Logged sets keep it** — see this type's note. A built-in term is refused.
    ///
    /// - Parameter modifier: The term to stop offering.
    /// - Returns: Whether anything was removed.
    @discardableResult
    public func remove(_ modifier: SetModifier) -> Bool {
        guard let position = custom.firstIndex(of: modifier.rawValue) else { return false }
        custom.remove(at: position)
        persist()
        return true
    }

    private func persist() {
        defaults.set(custom, forKey: Self.key)
    }

    /// The defaults key. T-1.60 migrates whatever is under it into the settings row.
    static let key = "logging.set-modifiers.custom"
}
