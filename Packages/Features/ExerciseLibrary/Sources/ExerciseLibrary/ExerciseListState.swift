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

        /// Every live exercise in the catalogue, archived ones included.
        ///
        /// **Archived rows are carried, not dropped.** Which of them the screen shows is
        /// ``ExerciseListState/showsArchived``'s answer, and a phase that had already discarded
        /// them would make that control a second read (`FR-1.1.5`).
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

    /// Whether archived exercises are shown alongside the rest (`FR-1.1.5`).
    ///
    /// **Not one of `FR-1.1.2`'s filters, and deliberately not ``clearFilters()``'s business.**
    /// Those four narrow a catalogue the user can already see; this one widens it to rows archiving
    /// took out of every picker. Clearing the filters is the way back from a search that matched
    /// nothing, and turning this off with them would hide rows the user had just asked to see.
    ///
    /// It exists because archiving with no way back is a trap: this is the only surface an archived
    /// exercise is reachable from, and un-archiving is on the detail screen behind it.
    public var showsArchived = false

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
            phase = .loaded(Self.ordered(try await repository.exercises(includingDeleted: false)))
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Re-reads the catalogue, keeping what is on screen until the new rows land.
    ///
    /// **This is what the screen's `.task` calls**, not ``load()``. A list returned to after a
    /// create or an edit above it (`FR-1.1.3`, `FR-1.1.4`) would otherwise show the rows it read the
    /// first time: ``load()`` refuses to run again once it has succeeded, which is exactly right for
    /// a re-established view identity and exactly wrong for a screen the user has just changed the
    /// data behind.
    ///
    /// **No ``Phase/loading`` in between.** A spinner over content that is already correct is a
    /// flash on every back-swipe; the rows are replaced when the read lands or the screen becomes
    /// its error state, and 116 local rows do not take long enough for a third state to be visible
    /// (`G-2.2`, `NFR-1.1`).
    ///
    /// A read that fails here **does** cost the list its rows, deliberately: the screen can no
    /// longer vouch for what it is showing, and ``Phase/failed(_:)`` is the state with the retry in
    /// it.
    public func refresh() async {
        switch phase {
        case .idle, .failed:
            await load()
            return
        case .loading:
            return
        case .loaded:
            break
        }
        do {
            phase = .loaded(Self.ordered(try await repository.exercises(includingDeleted: false)))
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Everything the repository returned, in the order every browsable surface in this module
    /// shares (``ExerciseOrder``).
    private static func ordered(_ exercises: [Exercise]) -> [Exercise] {
        exercises.sorted(by: ExerciseOrder.precedes)
    }

    /// The exercises the list may show, before the search text and the filters.
    ///
    /// **Archived rows leave here rather than through a filter binding**, because `FR-1.1.5` makes
    /// archiving the way an exercise leaves the pickers rather than one more way to narrow a list —
    /// ``showsArchived`` widens what is browsable, where every `FR-1.1.2` control narrows it, and
    /// the two must not be clearable by the same command.
    private var browsable: [Exercise] {
        guard case .loaded(let exercises) = phase else { return [] }
        return showsArchived ? exercises : exercises.filter { !$0.isArchived }
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
        browsable.filter { exercise in
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

    /// Whether the read succeeded and the store holds no exercise at all — a catalogue that failed
    /// to seed.
    ///
    /// **Measured over every row, archived ones included**, which is what keeps it a claim about the
    /// store rather than about the controls: a catalogue whose every row is archived is not empty,
    /// it is hidden, and the two want different answers on screen.
    public var isCatalogueEmpty: Bool {
        guard case .loaded(let exercises) = phase else { return false }
        return exercises.isEmpty
    }

    /// Whether every exercise there is has been archived and ``showsArchived`` is off.
    ///
    /// **The third empty state** (`FR-1.13.1`), and it is a separate fact from the two the list
    /// already had: an empty catalogue has nothing to show and nothing to undo, a search that
    /// matched nothing has the filters that caused it, and this has neither — the rows exist, they
    /// are archived, and the one control that brings them back is ``showsArchived``. Sending it to
    /// either of the others would offer a create form or a "clear filters" that changes nothing.
    public var isEverythingArchived: Bool {
        guard case .loaded(let exercises) = phase else { return false }
        return !showsArchived && !exercises.isEmpty && exercises.allSatisfy(\.isArchived)
    }

    /// Drops the search text and every filter — the action on the "nothing matched" state.
    ///
    /// ``showsArchived`` is untouched; see its own note for why it is not one of these.
    public func clearFilters() {
        searchText = ""
        movementFilter = nil
        equipmentFilter = nil
        originFilter = nil
    }
}
