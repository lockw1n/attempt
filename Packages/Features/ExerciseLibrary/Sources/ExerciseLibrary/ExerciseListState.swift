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
/// `async` signature, and 132 rows filter and group faster than a keystroke — so search does not
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

    /// Which of an exercise's two names this screen is showing (`FR-1.14.2`).
    ///
    /// It reaches ``groups`` twice over: the order rows come in, and which of them a search matches
    /// (`FR-1.14.3`). Set by the view, on ``RepositoryInterface/ExerciseNameLanguage``'s rule.
    public var nameLanguage: ExerciseNameLanguage = .english

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

    /// Show only exercises used recently, or every one (`FR-1.1.2`).
    ///
    /// One of the four narrowing controls, so ``clearFilters()`` turns it off — unlike
    /// ``showsArchived``, which widens.
    public var showsRecentOnly = false

    /// The exercises trained inside the recency window, or `nil` when the read has not answered.
    ///
    /// **A set of identifiers rather than a date per exercise.** The question the filter asks is a
    /// yes or no, and a per-exercise date would be a second ordering authority over a list whose
    /// order `FR-1.1.1` already fixes.
    public private(set) var recentExerciseIDs: Set<UUID>?

    /// How far back "recently used" reaches, in days.
    ///
    /// **A rolling window rather than the last *n* sessions**, and the two are not the same
    /// promise. A last-*n* rule always returns something, so a lifter six months out of the gym is
    /// shown their last session's exercises as "recent" — a filter that lies, in the one case where
    /// the honest answer is that nothing is. A window answers "nothing" there, and for anyone
    /// training normally it answers with the block they are in the middle of.
    ///
    /// **Thirty days rather than seven**, because a powerlifting programme rotates: a squat variant
    /// trained every third week is used recently, and a week-long window would call it forgotten.
    public static let recencyWindowInDays = 30

    /// Whether `FR-1.1.2`'s recency filter can be offered.
    ///
    /// **The read having answered is not enough — it has to have found something.** A chip that can
    /// be tapped only to empty the list is a control that appears broken; the hint beside it says
    /// what turns it on instead. It stays disabled rather than hidden for that same reason, which is
    /// the reading T-1.10 shipped and this task keeps.
    public var isRecencyFilterAvailable: Bool {
        recentExerciseIDs?.isEmpty == false
    }

    private let repository: any ExerciseRepository
    private let workouts: any WorkoutRepository

    /// Builds the state over the two repositories it reads through.
    ///
    /// - Parameters:
    ///   - repository: The catalogue (`FR-1.1.1`).
    ///   - workouts: What has been logged, for `FR-1.1.2`'s recency filter and nothing else. A
    ///     second protocol rather than a dependency on `Logging`, which this module must not have
    ///     (`TR-1.3`) — both modules already depend on `RepositoryInterface`, and the app target
    ///     composes them.
    public init(repository: any ExerciseRepository, workouts: any WorkoutRepository) {
        self.repository = repository
        self.workouts = workouts
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
            phase = .loaded(try await repository.exercises(includingDeleted: false))
        } catch {
            phase = .failed(String(describing: error))
        }
        await loadRecentlyUsed()
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
    /// its error state, and 132 local rows do not take long enough for a third state to be visible
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
            phase = .loaded(try await repository.exercises(includingDeleted: false))
        } catch {
            phase = .failed(String(describing: error))
        }
        await loadRecentlyUsed()
    }

    /// Reads which exercises have been trained inside the recency window (`FR-1.1.2`).
    ///
    /// **Two levels of read, because the schema declares no relationships** (`G-2.5`): the sessions
    /// in the window, then each one's entries. It is a bounded read by construction — a month of
    /// training is a few dozen rows — and it runs beside the catalogue read rather than on a tap, so
    /// the chip's own state is settled before the user can reach for it.
    ///
    /// **A failure disables the filter rather than failing the screen.** The catalogue is what this
    /// list is; recency narrows it. Losing the rows to a read that only ever governed one chip would
    /// be a screen taken down by its least important query — so the diagnostic is that the chip goes
    /// back to being unavailable, and a filter left in force is turned off with it rather than
    /// silently narrowing to a set nobody can vouch for.
    ///
    /// **A window that comes back empty ends the same way, and for a sharper reason.** There the
    /// filter narrows to nothing at all, behind a chip that is now disabled — so the list is empty
    /// and the control that would undo it cannot be tapped.
    private func loadRecentlyUsed() async {
        let now = Date.now
        guard
            let start = Calendar.current.date(
                byAdding: .day, value: -Self.recencyWindowInDays, to: now)
        else {
            return
        }
        do {
            var used: Set<UUID> = []
            for session in try await workouts.sessions(in: start...now, includingDeleted: false) {
                let entries = try await workouts.entries(
                    forSessionID: session.id, includingDeleted: false)
                used.formUnion(entries.map(\.exerciseID))
            }
            recentExerciseIDs = used
        } catch {
            recentExerciseIDs = nil
        }
        // One clause for both endings, because they are one fact: a filter cannot stay in force
        // while the chip that would clear it is disabled.
        if !isRecencyFilterAvailable { showsRecentOnly = false }
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
    ///
    /// **Ordered here rather than at the read**, because ``nameLanguage`` decides the order and may
    /// be set after one: a screen that sorted its rows when they arrived would keep an English order
    /// under Ukrainian names (`FR-1.14.2`). The sort runs on every read of this property, so a
    /// caller that needs it twice reads it once into a local.
    public var groups: [ExerciseGroup] {
        let matches = filtered
        return Movement.allCases.compactMap { movement in
            let exercises = ExerciseDisplayOrder.sorted(
                matches.filter { $0.movement == movement }, in: nameLanguage)
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
                && matchesRecency(exercise)
        }
    }

    /// Whether `exercise` survives `FR-1.1.2`'s recency filter.
    ///
    /// Everything survives while the filter is off, and while the read that would answer it has not
    /// — a narrowing nobody asked for is worse than one that is briefly not offered.
    private func matchesRecency(_ exercise: Exercise) -> Bool {
        guard showsRecentOnly, let recent = recentExerciseIDs else { return true }
        return recent.contains(exercise.id)
    }

    /// Whether the name this row is showing matches what the user typed (`FR-1.14.3`).
    ///
    /// `localizedStandardContains` is the search a user expects and the one a hand-rolled
    /// `lowercased().contains` is not: it ignores case *and* diacritics, so "sumo" finds "Sumó" and
    /// a Turkish locale does not lose the dotted I. Whitespace-only input is no search at all —
    /// otherwise the first space typed empties the screen.
    ///
    /// **Matched against the resolved display name, never against ``RepositoryInterface/Exercise``'s
    /// two fields in turn.** `FR-1.14.3` says the name shown, and the two readings disagree exactly
    /// where it matters: an English query would otherwise find a row whose visible name is Cyrillic
    /// and holds none of what was typed, and a Ukrainian name left as whitespace — which
    /// ``RepositoryInterface/Exercise/displayName(in:)`` deliberately renders as the English one —
    /// would be searchable under a name nothing on screen says.
    private func matchesSearch(_ exercise: Exercise) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return exercise.displayName(in: nameLanguage).localizedStandardContains(query)
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
        showsRecentOnly = false
    }
}
