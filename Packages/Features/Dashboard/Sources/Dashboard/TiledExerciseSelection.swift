import DerivedValues
import Foundation
import RepositoryInterface

/// One row of the picker: an exercise, and whether it is tiled (`FR-1.9.1`).
struct TiledExerciseChoice: Identifiable, Sendable, Equatable {
    /// The exercise. Also the row's identity.
    let exerciseID: UUID

    /// Its name, drawn `verbatim` — a catalogue row is data, not copy (`G-3.4`).
    let name: String

    /// Whether it currently has a tile.
    let isTiled: Bool

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
    /// Every choice, ordered by name.
    private(set) var choices: [TiledExerciseChoice] = []

    /// Which exercises are tiled, in the order they are drawn.
    private(set) var selection: [UUID] = []

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

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - catalogue: The exercises to choose among.
    ///   - settings: Where the selection is stored.
    init(catalogue: any ExerciseRepository, settings: any SettingsRepository) {
        self.catalogue = catalogue
        self.settings = settings
    }

    /// Which of an exercise's two names a row shows, and orders by (`FR-1.14.2`).
    ///
    /// Set by the view from `@Environment(\.locale)`, for the reason
    /// ``EstimatedMaxTilesState/nameLanguage`` gives — a row's name is a string this state builds.
    var nameLanguage: ExerciseNameLanguage = .english

    /// Reads the catalogue and the selection.
    ///
    /// The selection defaults exactly as the tiles do — ``DashboardDefaults`` — so the picker opens
    /// showing the three the user can already see, rather than nothing ticked under three tiles.
    ///
    /// **A fresh read retires ``writeFailure``**, the rule ``LastWorkoutState/load()`` states: a
    /// failed toggle is reported beside the rows it did not change, and those rows are exactly what
    /// this replaces.
    func load() async {
        writeFailure = nil
        do {
            let stored = try await settings.settings()
            let exercises = try await catalogue.exercises(includingDeleted: false)
            let chosen = stored.dashboardExerciseIDs ?? DashboardDefaults.exerciseIDs(in: exercises)
            let tiled = Set(chosen)
            selection = chosen
            choices =
                exercises
                .filter { !$0.isArchived || tiled.contains($0.id) }
                .sorted { Self.precedes($0, $1, in: nameLanguage) }
                .map {
                    TiledExerciseChoice(
                        exerciseID: $0.id,
                        name: $0.displayName(in: nameLanguage),
                        isTiled: tiled.contains($0.id))
                }
            failure = nil
        } catch {
            failure = String(describing: error)
        }
        hasLoaded = true
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

    /// Whether `lhs`'s row is shown before `rhs`'s, by the name the rows carry (`FR-1.14.2`).
    ///
    /// `localizedStandardCompare` rather than `<`, which is the byte order and puts every Cyrillic
    /// name after every Latin one. The identifier breaks a tie because `G-2.5` forbids a unique
    /// constraint on the name and `Array.sorted` is not stable: two exercises reading alike would
    /// otherwise swap places between two reads of one catalogue.
    ///
    /// - Parameters:
    ///   - lhs: The candidate for the earlier row.
    ///   - rhs: The one it is compared against.
    ///   - language: Which name the rows are showing.
    /// - Returns: `true` when `lhs` sorts first.
    private static func precedes(
        _ lhs: Exercise, _ rhs: Exercise, in language: ExerciseNameLanguage
    ) -> Bool {
        let byName = lhs.displayName(in: language)
            .localizedStandardCompare(rhs.displayName(in: language))
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
