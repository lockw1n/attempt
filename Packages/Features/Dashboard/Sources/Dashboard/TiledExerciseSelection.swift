import DerivedValues
import Foundation
import RepositoryInterface

/// One row of the picker: an exercise, whether it is tiled, and when it was last trained
/// (`FR-1.9.1`, `FR-16.5.3`).
struct TiledExerciseChoice: Identifiable, Sendable, Equatable {
    /// The exercise. Also the row's identity.
    let exerciseID: UUID

    /// Its name, drawn `verbatim` — a catalogue row is data, not copy (`G-3.4`).
    let name: String

    /// Whether it currently has a tile.
    let isTiled: Bool

    /// The day this exercise was last trained inside the lookback window, or `nil` where it was not
    /// trained in it at all (`FR-16.5.3`).
    ///
    /// **Presence is what puts the row in the Trained section**, so this is one fact rather than a
    /// flag and a date that could disagree. `nil` means "not in the window", never "trained on an
    /// unknown day": ``DerivedValues/PersonalRecordRecomputer/lastTrainedDates()`` answers with a
    /// date or with nothing.
    ///
    /// **No default.** A caller that has not decided whether its rows carry dates has not decided
    /// which section they land in, and a defaulted `nil` would silently put every row in
    /// **Everything else**.
    let lastTrained: Date?

    /// See `Identifiable`.
    var id: UUID { exerciseID }
}

/// The picker's own state: every exercise that can be tiled, and which ones are (`FR-1.9.1`).
///
/// **The selection is written straight through on every toggle**, not gathered and saved on the way
/// out. It is the posture every write in this app takes (`NFR-1.8`), and it is what makes the screen
/// have no Save button to forget: a tile removed is removed, and the dashboard behind this is already
/// showing it.
///
/// **Archived exercises are absent** (`FR-1.1.5`): archiving is how an exercise leaves the pickers,
/// and this is one. An archived exercise that is *already* tiled stays tiled and stays listed —
/// hiding it would leave a tile the user could see and not remove.
@Observable
final class TiledExerciseSelectionState {
    /// Every choice, ordered by name (`FR-1.14.2`) — the population ``sections`` splits.
    private(set) var choices: [TiledExerciseChoice] = []

    /// What the user typed into the search field (`FR-16.5.3`).
    ///
    /// Here rather than in the view, for the exercise list's reason: a claim about what a search
    /// returns is testable only where the results are computed.
    var searchText = ""

    /// The rows the screen draws: trained first, then the rest, both narrowed by ``searchText``.
    var sections: [ExerciseChoiceSection] {
        ExerciseChoiceSections.sections(choices, matching: searchText)
    }

    /// Which exercises are tiled, in the order they are drawn.
    private(set) var selection: [UUID] = []

    /// ``trainedDates()``' one answer for this visit, or `nil` while it has not been read.
    private var lastTrained: [UUID: Date]?

    /// Whether the first read has answered.
    private(set) var hasLoaded = false

    /// Why the read failed, or `nil`.
    private(set) var failure: String?

    /// Why the last toggle could not be stored, or `nil`. Nothing changed when it is set.
    private(set) var writeFailure: String?

    /// The catalogue.
    private let catalogue: any ExerciseRepository

    /// The settings row, which carries the selection.
    private let settings: any SettingsRepository

    /// The recompute actor, for the ranking `FR-16.5.1`'s defaults fall back to. Read only where
    /// the lifter has chosen nothing — see ``EstimatedMaxTilesState/selection(_:in:from:)``.
    private let records: PersonalRecordRecomputer

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - catalogue: The exercises to choose among.
    ///   - settings: Where the selection is stored.
    ///   - records: The app's one recompute actor, for the defaults' fallback ranking.
    init(
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer
    ) {
        self.catalogue = catalogue
        self.settings = settings
        self.records = records
    }

    /// Which of an exercise's two names a row shows, and orders by (`FR-1.14.2`).
    ///
    /// A row's name is a string this state builds — the view sets this, on
    /// ``RepositoryInterface/ExerciseNameLanguage``'s rule.
    var nameLanguage: ExerciseNameLanguage = .english

    /// Reads the catalogue and the selection.
    ///
    /// The selection defaults exactly as the tiles do — ``DashboardDefaults`` — so the picker opens
    /// showing the three the user can already see, rather than nothing ticked under three tiles.
    ///
    /// **Two reads of the same bounded walk, and they answer different questions** (`FR-16.5.3`):
    /// ``EstimatedMaxTilesState/selection(_:in:from:)`` asks which lifts a lifter who has chosen
    /// nothing gets, and ``trainedDates()`` asks when each exercise was last trained. The second
    /// runs whatever the first answered — a configured dashboard still wants its **Trained**
    /// section — but only once per visit; see ``trainedDates()``.
    ///
    /// **A fresh read retires ``writeFailure``**, the rule ``LastWorkoutState/load()`` states: a
    /// failed toggle is reported beside the rows it did not change, and those rows are exactly what
    /// this replaces.
    func load() async {
        writeFailure = nil
        do {
            let stored = try await settings.settings()
            let exercises = try await catalogue.exercises(includingDeleted: false)
            let chosen = try await EstimatedMaxTilesState.selection(
                stored, in: exercises, from: records)
            let trained = try await trainedDates()
            let tiled = Set(chosen)
            selection = chosen
            choices = ExerciseDisplayOrder.sorted(
                exercises.filter { !$0.isArchived || tiled.contains($0.id) }, in: nameLanguage
            )
            .map {
                TiledExerciseChoice(
                    exerciseID: $0.id,
                    name: $0.displayName(in: nameLanguage),
                    isTiled: tiled.contains($0.id),
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
    /// **A toggle changes no session, so the dates a reload would fetch cannot have moved.**
    /// ``toggle(_:)`` ends in ``load()``, and
    /// ``DerivedValues/PersonalRecordRecomputer/lastTrainedDates()`` walks every session in the
    /// lookback window and every set under each one — a walk this screen would otherwise pay on
    /// every tap, on a screen a lifter taps several times in a row (`NFR-1.6`). Nothing can log a
    /// workout while the picker is up, so one read per visit is the whole of what
    /// `FR-16.5.3`'s **Trained** section needs.
    ///
    /// A read that throws leaves ``lastTrained`` unset and is retried with the rest of ``load()``,
    /// so a cached answer is only ever one that succeeded.
    ///
    /// - Returns: The most recent session date per exercise, for exercises trained in the window.
    private func trainedDates() async throws -> [UUID: Date] {
        if let lastTrained { return lastTrained }
        let dates = try await records.lastTrainedDates()
        lastTrained = dates
        return dates
    }

    /// Adds or removes one exercise's tile, and stores the result (`FR-1.9.1`).
    ///
    /// **An added exercise goes to the end**, which is what makes the order the user's: the three
    /// defaults keep the requirement's own order until something is added, and nothing they have
    /// already arranged moves when they add a fourth.
    ///
    /// - Parameter exerciseID: The exercise to toggle.
    func toggle(_ exerciseID: UUID) async {
        let next =
            selection.contains(exerciseID)
            ? selection.filter { $0 != exerciseID } : selection + [exerciseID]
        do {
            let stored = try await settings.settings()
            try await settings.save(stored.tiling(next))
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
            return
        }
        await load()
    }

}
