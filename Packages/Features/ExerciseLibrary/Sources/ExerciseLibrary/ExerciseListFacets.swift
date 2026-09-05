import Foundation
import PowerliftingCore

/// One narrowing the list is under, as the folded filter row shows it (`FR-16.5.4`).
///
/// **A value rather than a rendered label**, so the row that lists the active facets is computed
/// where the facets are and the copy stays in `ExerciseLibraryStrings`. Tapping one clears it, which
/// is why each case carries the value it is set to rather than only naming its facet.
public enum ExerciseListFacet: Sendable, Hashable {
    /// Narrowed to one movement.
    case movement(Movement)

    /// Narrowed to one implement.
    case equipment(Equipment)

    /// Narrowed to the user's own exercises, or to the seeded ones.
    case origin(ExerciseOrigin)

    /// Narrowed to what has been trained inside the recency window (`FR-1.1.2`).
    case recentlyUsed

    /// Widened to archived exercises (`FR-1.1.5`).
    ///
    /// **Listed beside the four that narrow, and it is still not one of them.** It is here because
    /// `FR-16.5.4` puts every filter control on one row and a control the user turned on has to be
    /// visible while the row is folded — ``ExerciseListState/clearFilters()`` still leaves it alone.
    case archived
}

/// The four narrowing controls, as one value (`FR-16.5.4`).
///
/// Together rather than separately because they are remembered together: what the list reopens on
/// is the set of choices the lifter last made, not four independent memories.
public struct ExerciseListFacets: Sendable, Equatable {
    /// Show only this movement, or every movement.
    public var movement: Movement?

    /// Show only exercises performed with this, or every one.
    public var equipment: Equipment?

    /// Show only built-in or only custom exercises, or both.
    public var origin: ExerciseOrigin?

    /// Show only exercises used recently, or every one.
    public var showsRecentOnly = false

    /// Everything, which is where a list with no history opens.
    public init() {}
}

/// Where the exercise list's facet choices live between two visits inside one launch
/// (`FR-16.5.4`).
///
/// **Process-lifetime and deliberately not persisted.** The requirement says "remembered for the
/// session", and the two readings differ in what a lifter finds tomorrow: a stored filter is one
/// they have to remember setting and can be confused by weeks later, where a session-long one is
/// obviously theirs. `UserSettings` is where a preference would go, and no requirement asks for one.
///
/// **One memory for the browsing list and the chooser**, which are the same screen under two
/// closures — a lifter who narrows to *bench* to pick an exercise wants the same narrowing when they
/// go looking at the catalogue a moment later.
@MainActor
public final class ExerciseListFilterMemory {
    /// The app's one memory. A test builds its own instead.
    public static let shared = ExerciseListFilterMemory()

    /// What was last chosen, or `nil` while nothing has been chosen this launch.
    ///
    /// **`nil` is not "everything".** It is what lets the list open on `FR-16.5.4`'s **Recently
    /// used** default the first time and honour a lifter who cleared every facet the second — the
    /// two are the same four values and different intentions.
    public private(set) var facets: ExerciseListFacets?

    /// Builds an empty memory.
    public init() {}

    /// Records a choice.
    ///
    /// - Parameter facets: What the four controls are now set to.
    public func remember(_ facets: ExerciseListFacets) {
        self.facets = facets
    }
}
