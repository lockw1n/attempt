import DerivedValues
import Foundation
import RepositoryInterface

/// `FR-17.3.3`'s picker: which lifts the recent-PR feed reports on under `FR-16.3.1`'s `.chosen`
/// scope.
///
/// **Its own state over the same settings row, rather than the configuration screen's.** The route
/// carries no payload — a restored stack decodes before any store is read — so the app target builds
/// this screen from the route alone, and a state shared with the screen that pushed it would have to
/// survive that. What carries a tick back to the configuration row's count and to the feed is
/// ``DerivedValues/PersonalRecordRecomputer/recentRecordsPreferencesDidChange()`` (`TR-1.5`).
///
/// **Archived exercises are listed**, unlike ``TiledExerciseSelectionState``'s: this is the list
/// T-16.07 shipped inline, moved rather than changed, and a scope naming a retired movement is a
/// selection the lifter still has to be able to untick.
@Observable
final class RecentRecordsExercisesState {
    /// Every choice, ordered by name (`FR-1.14.2`) — the population ``sections`` splits.
    private(set) var choices: [TiledExerciseChoice] = []

    /// What the user typed into the search field (`FR-16.5.3`).
    var searchText = ""

    /// The rows the screen draws: trained first, then the rest, both narrowed by ``searchText``.
    var sections: [ExerciseChoiceSection] {
        ExerciseChoiceSections.sections(choices, matching: searchText)
    }

    /// ``trainedDates()``' one answer for this visit, or `nil` while it has not been read.
    private var lastTrained: [UUID: Date]?

    /// Whether the first read has answered.
    private(set) var hasLoaded = false

    /// Why the read failed, or `nil`.
    private(set) var failure: String?

    /// Why the last tick could not be stored, or `nil`. Nothing changed when it is set.
    private(set) var writeFailure: String?

    /// Which of an exercise's two names a row shows, and orders by (`FR-1.14.2`).
    var nameLanguage: ExerciseNameLanguage = .english

    /// Where the selection is stored.
    @ObservationIgnored private let settings: any SettingsRepository

    /// The exercises to choose among.
    @ObservationIgnored private let catalogue: any ExerciseRepository

    /// What is told that the row moved, so the feed re-reads without being revisited (`TR-1.5`).
    @ObservationIgnored private let recomputer: PersonalRecordRecomputer

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - settings: Where the selection is stored.
    ///   - catalogue: The exercises to choose among.
    ///   - records: The app's one recompute actor — the announcement the feed listens for.
    init(
        settings: any SettingsRepository,
        catalogue: any ExerciseRepository,
        records: PersonalRecordRecomputer
    ) {
        self.settings = settings
        self.catalogue = catalogue
        self.recomputer = records
    }

    /// Reads the catalogue and the selection.
    ///
    /// **A fresh read retires ``writeFailure``**, `TiledExerciseSelectionState/load()`'s rule: a
    /// failed tick is reported beside the rows it did not change, and those rows are exactly what
    /// this replaces.
    func load() async {
        writeFailure = nil
        do {
            let stored = try await settings.settings()
            let exercises = try await catalogue.exercises(includingDeleted: false)
            let chosen = Set(stored.recentRecordsExerciseIDs ?? [])
            let trained = try await trainedDates()
            choices = ExerciseDisplayOrder.sorted(exercises, in: nameLanguage).map {
                TiledExerciseChoice(
                    exerciseID: $0.id,
                    name: $0.displayName(in: nameLanguage),
                    isTiled: chosen.contains($0.id),
                    lastTrained: trained[$0.id])
            }
            failure = nil
        } catch {
            failure = String(describing: error)
        }
        hasLoaded = true
    }

    /// When each exercise was last trained, read once per visit rather than once per load.
    ///
    /// ``TiledExerciseSelectionState/trainedDates()``' reason: ``toggle(_:)`` ends in ``load()``,
    /// so a lifter ticking six lifts in a row would otherwise walk every session in the lookback
    /// window six times (`NFR-1.6`), and a tick changes no session.
    ///
    /// - Returns: The most recent session date per exercise, for exercises trained in the window.
    private func trainedDates() async throws -> [UUID: Date] {
        if let lastTrained { return lastTrained }
        let dates = try await recomputer.lastTrainedDates()
        lastTrained = dates
        return dates
    }

    /// Adds or removes one lift from the feed's scope, and stores the result (`FR-16.3.1`).
    ///
    /// An added exercise goes to the end, on `TiledExerciseSelectionState/toggle(_:)`'s rule.
    ///
    /// **It re-reads the row before writing rather than saving a copy this screen holds**, which is
    /// `UserSettings`' own rule about the stale-write shape — and load-bearing here, since the
    /// screen that pushed this one writes the same row.
    ///
    /// - Parameter exerciseID: The exercise to toggle.
    func toggle(_ exerciseID: UUID) async {
        do {
            var stored = try await settings.settings()
            let current = stored.recentRecordsExerciseIDs ?? []
            stored.recentRecordsExerciseIDs =
                current.contains(exerciseID)
                ? current.filter { $0 != exerciseID } : current + [exerciseID]
            try await settings.save(stored)
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
            return
        }
        // The feed is on another tab and is not revisited on the way back (`TR-1.5`).
        await recomputer.recentRecordsPreferencesDidChange()
        await load()
    }
}
