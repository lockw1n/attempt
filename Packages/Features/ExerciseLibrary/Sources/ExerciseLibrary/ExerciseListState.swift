import Foundation
import PowerliftingCore
import RepositoryInterface

/// Whether an exercise came from the seed catalogue or from the user (`FR-1.1.2`).
///
/// A filter over ``RepositoryInterface/Exercise/isCustom`` rather than a second spelling of it: the
/// screen's control has three positions and the record's flag has two, and "either" is the position
/// the flag cannot express.
public enum ExerciseOrigin: String, Sendable, Hashable, CaseIterable {
    /// Seeded from `exercises.json` (`TR-0.5.1`).
    case builtIn

    /// Authored by the user (`FR-1.1.3`).
    case custom
}

/// One movement's exercises, as the list renders them (`FR-1.1.1`).
public struct ExerciseGroup: Sendable, Hashable, Identifiable {
    /// The movement every exercise in this group trains. Also the group's identity: a movement
    /// appears once.
    public let movement: Movement

    /// Its exercises, in the order they are shown.
    public let exercises: [Exercise]

    /// ``movement``, so the group survives a reorder without the list rebuilding every row.
    public var id: Movement { movement }
}

/// The exercise library's list screen, as state rather than as a view model (`TR-1.2`, `FR-1.1.1`,
/// `FR-1.1.2`).
///
/// The pattern is `SettingsLandingState`'s, and the part worth restating is why the filtering lives
/// here: every claim in `FR-1.1.2` is a claim about which exercises come back, and a claim about
/// results is testable only where the results are computed. ``groups`` is derived on read from the
/// loaded rows and the four controls, so a test sets a control and reads the answer without
/// rendering anything.
///
/// **The catalogue is read once.** `G-2.2`/`G-2.3` make the local store's read synchronous under an
/// `async` signature, and 116 rows filter and group faster than a keystroke — so search does not
/// return to the repository, and there is no debounce to get wrong (`NFR-1.1`).
@Observable
public final class ExerciseListState {
    /// What the screen has to show, as one value rather than three flags. See
    /// `Settings.SettingsLandingState.Phase`, which this mirrors deliberately.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet. ``ExerciseListState/load()`` moves out of this.
        case idle

        /// A read is in flight.
        case loading

        /// The catalogue, already stripped of archived rows.
        case loaded([Exercise])

        /// The read failed, carrying the error's description.
        ///
        /// A **diagnostic**, not copy (`G-3.4`) — the screen shows its own sentence and never this
        /// string. **Recoverable**: ``ExerciseListState/load()`` runs again from here.
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// What the user typed into the search field (`FR-1.1.1`).
    public var searchText: String = ""

    /// Show only this movement, or every movement (`FR-1.1.2`).
    public var movementFilter: Movement?

    /// Show only exercises performed with this, or every one (`FR-1.1.2`).
    public var equipmentFilter: Equipment?

    /// Show only built-in or only custom exercises, or both (`FR-1.1.2`).
    public var originFilter: ExerciseOrigin?

    /// Whether `FR-1.1.2`'s recency filter can be offered yet.
    ///
    /// **`false`, and the screen shows the control disabled rather than hiding it.** Recency is a
    /// read over logged sets, and nothing has logged one until Track C lands — a control that
    /// silently returned everything would be a filter that lies, and a missing control would be a
    /// requirement nobody can see is unfinished. The filter itself is T-1.21's to wire, when a
    /// session exists to be recent.
    public let isRecencyFilterAvailable = false

    private let repository: any ExerciseRepository

    /// Builds the state over the repository it reads through.
    public init(repository: any ExerciseRepository) {
        self.repository = repository
    }

    /// Reads the catalogue, on first appearance and on every retry.
    ///
    /// Re-entrant only through ``Phase/loading``, for the reason `SettingsLandingState.load()`
    /// gives: SwiftUI runs `.task` again whenever the view's identity is re-established, and two
    /// reads in flight would publish whichever finished last.
    public func load() async {
        switch phase {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        phase = .loading
        do {
            phase = .loaded(Self.browsable(try await repository.exercises(includingDeleted: false)))
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// The exercises the list may show, from everything the repository returned.
    ///
    /// **Archived rows are dropped here rather than by a control**, because `FR-1.1.5` makes
    /// archiving the way an exercise leaves the pickers — it is not one of `FR-1.1.2`'s filters and
    /// must not be reachable as one. T-1.13 adds the archiving; the exclusion is written now so that
    /// task changes a screen's behaviour and not this rule.
    ///
    /// The order is ``ExerciseOrder``'s, which every browsable surface in this module shares.
    private static func browsable(_ exercises: [Exercise]) -> [Exercise] {
        exercises.filter { !$0.isArchived }.sorted(by: ExerciseOrder.precedes)
    }

    /// The catalogue after the search text and every filter, grouped by movement (`FR-1.1.1`).
    ///
    /// Groups follow ``PowerliftingCore/Movement``'s own case order, so the competition lifts lead
    /// and `other` trails — a list ordered by however many exercises happen to sit under each
    /// heading would reorder itself as the user adds their own. A movement with nothing left in it
    /// is dropped: an empty heading says a filter matched when it did not.
    public var groups: [ExerciseGroup] {
        let matches = filtered
        return Movement.allCases.compactMap { movement in
            let exercises = matches.filter { $0.movement == movement }
            return exercises.isEmpty ? nil : ExerciseGroup(movement: movement, exercises: exercises)
        }
    }

    /// Every loaded exercise that survives the search text and the filters.
    private var filtered: [Exercise] {
        guard case .loaded(let exercises) = phase else { return [] }
        return exercises.filter { exercise in
            matchesSearch(exercise)
                && (movementFilter == nil || exercise.movement == movementFilter)
                && (equipmentFilter == nil || exercise.equipment == equipmentFilter)
                && (originFilter == nil || origin(of: exercise) == originFilter)
        }
    }

    /// Whether `exercise`'s name matches what the user typed.
    ///
    /// `localizedStandardContains` is the search a user expects and the one a hand-rolled
    /// `lowercased().contains` is not: it ignores case *and* diacritics, so "sumo" finds "Sumó" and
    /// a Turkish locale does not lose the dotted I. Whitespace-only input is no search at all —
    /// otherwise the first space typed empties the screen.
    private func matchesSearch(_ exercise: Exercise) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return exercise.name.localizedStandardContains(query)
    }

    /// Which side of `FR-1.1.2`'s custom/built-in split an exercise falls on.
    private func origin(of exercise: Exercise) -> ExerciseOrigin {
        exercise.isCustom ? .custom : .builtIn
    }

    /// Whether the read succeeded and there is nothing at all to browse — a catalogue that failed to
    /// seed, or one every row of which is archived.
    ///
    /// **This and an empty ``groups`` are what tell the two empty screens apart** (`FR-1.13.1`):
    /// true here is a catalogue with nothing in it and nothing to undo, where empty groups under a
    /// non-empty catalogue is a search that matched nothing and offers the way back. Nothing narrows
    /// a loaded catalogue to no groups without a control being set, so the second needs no flag of
    /// its own.
    public var isCatalogueEmpty: Bool {
        guard case .loaded(let exercises) = phase else { return false }
        return exercises.isEmpty
    }

    /// Drops the search text and every filter — the action on the "nothing matched" state.
    public func clearFilters() {
        searchText = ""
        movementFilter = nil
        equipmentFilter = nil
        originFilter = nil
    }
}
