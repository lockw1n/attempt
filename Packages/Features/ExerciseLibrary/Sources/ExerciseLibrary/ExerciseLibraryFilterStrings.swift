import Foundation

/// `FR-16.5.4`'s copy: the control that folds the facets, and the chips that say what is in force
/// while they are folded.
///
/// A file of its own rather than more of ``ExerciseLibraryStrings``, which had reached SwiftLint's
/// length ceiling. Same type, same catalogue, same key convention.
extension ExerciseLibraryStrings {
    /// The control that opens the folded filter row.
    static let filtersLabel = resource("exerciselibrary.list.filter.filters")

    /// What that control does, for VoiceOver — the chip itself says only "Filters", which names the
    /// subject and not the act (`G-4.2`).
    static let filtersHint = resource("exerciselibrary.list.filter.filters.hint")

    /// What tapping an active chip in the folded row does, where the chip is a narrowing.
    static let clearFilterHint = resource("exerciselibrary.list.filter.clear.hint")

    /// The same for ``ExerciseListFacet/archived``, which widens where the other four narrow, so
    /// clearing it takes rows away rather than giving them back — one hint over both would be wrong
    /// about exactly the chip the row already treats as the exception.
    static let hideArchivedHint = resource("exerciselibrary.list.filter.hide-archived.hint")

    /// One narrowing in force, as the folded row's chip names it.
    ///
    /// **It delegates to the four labels rather than owning six more keys.** A chip in the folded
    /// row and the chip inside the facet row are the same filter, so a second spelling would be a
    /// second thing to translate and one more way for the two to disagree about what is selected.
    ///
    /// - Parameter facet: The narrowing.
    /// - Returns: Its label.
    static func label(for facet: ExerciseListFacet) -> LocalizedStringResource {
        switch facet {
        case .movement(let movement): label(for: movement)
        case .equipment(let equipment): label(for: equipment)
        case .origin(let origin): label(for: origin)
        case .recentlyUsed: recentlyUsedFilter
        case .archived: showArchivedFilter
        }
    }

    /// What tapping one of the folded row's active chips does, for VoiceOver.
    ///
    /// - Parameter facet: The narrowing the chip names.
    /// - Returns: What the tap will do.
    static func clearHint(for facet: ExerciseListFacet) -> LocalizedStringResource {
        switch facet {
        case .archived: hideArchivedHint
        default: clearFilterHint
        }
    }
}
