import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// One tile: the exercise it names, and what that exercise's estimated maximum currently is
/// (`FR-1.9.1`).
///
/// The estimate arrives whole rather than unpacked into a number and a reason — a tile switches on
/// ``DerivedValues/EstimatedMax/content`` exactly as the exercise detail's section does, so the
/// seven refusals stay one vocabulary with one home (`FR-1.13.3`).
struct EstimatedMaxTile: Identifiable, Sendable, Equatable {
    /// The exercise, which is also the tile's identity: the same exercise is never tiled twice.
    let exerciseID: UUID

    /// Its name. `verbatim` when drawn — a catalogue row is data, not copy (`G-3.4`).
    let name: String

    /// The estimate, the override, or the reason there is neither.
    let estimate: EstimatedMax

    /// See ``Identifiable``.
    var id: UUID { exerciseID }
}

/// The tiles' own read (`FR-1.9.1`), and the selection behind them.
///
/// **One state for both halves, because a tile cannot be built from either alone**: the settings row
/// says which exercises, the catalogue names them, and the recompute actor values them. Splitting it
/// would mean three screens' worth of reads to draw one card.
///
/// **It subscribes as well as reads** (`TR-1.5`), so a set logged in another tab, or a formula chosen
/// in Settings, moves these numbers without the tab being revisited.
@Observable
final class EstimatedMaxTilesState {
    /// The tiles, in the selection's order. An identifier the catalogue cannot resolve is **absent**
    /// rather than drawn empty: a tiled exercise can be deleted, and `G-2.5` forbids the constraint
    /// that would stop it.
    private(set) var tiles: [EstimatedMaxTile] = []

    /// Which exercises are tiled, as stored or as defaulted — what the picker opens holding.
    private(set) var selection: [UUID] = []

    /// Whether the user has ever chosen. `false` means ``selection`` is ``DashboardDefaults``'.
    private(set) var isConfigured = false

    /// Whether the first read has answered. See ``DerivedValues/ExerciseRecordsState``.
    private(set) var hasLoaded = false

    /// Why the read failed, or `nil`. A retry may work.
    private(set) var failure: String?

    /// Why the last selection write failed, or `nil`. The tiles on screen are unchanged either way.
    private(set) var writeFailure: String?

    /// The unit the loads are shown in (`G-3.1`) — read here rather than by each tile, since one
    /// settings read already answers it.
    private(set) var unit: MassUnit = .kilograms

    /// The app's one recompute actor (`TR-1.6`).
    private let records: PersonalRecordRecomputer

    /// The catalogue: which exercises the defaults resolve to, and what each tile is called.
    private let catalogue: any ExerciseRepository

    /// The settings row, which carries both the selection and the display unit.
    private let settings: any SettingsRepository

    /// Builds the state over the three things a tile is made of.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor.
    ///   - catalogue: The exercises.
    ///   - settings: The settings row (`FR-1.9.1`'s selection, `G-3.1`'s unit).
    init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        self.records = records
        self.catalogue = catalogue
        self.settings = settings
    }

    /// Reads the selection, resolves it against the catalogue and values every tile.
    ///
    /// **The estimates are read one exercise at a time and there are three of them**, which is the
    /// bound that keeps this off `NFR-1.6`'s slow path: the number of reads is the number of tiles
    /// the user chose, never the size of the catalogue.
    func load() async {
        do {
            let stored = try await settings.settings()
            let exercises = try await catalogue.exercises(includingDeleted: false)
            let chosen = stored.dashboardExerciseIDs ?? DashboardDefaults.exerciseIDs(in: exercises)
            let named = Dictionary(exercises.map { ($0.id, $0.name) }) { first, _ in first }
            var built: [EstimatedMaxTile] = []
            for exerciseID in chosen {
                guard let name = named[exerciseID] else { continue }
                built.append(
                    EstimatedMaxTile(
                        exerciseID: exerciseID,
                        name: name,
                        estimate: try await records.estimatedMax(forExerciseID: exerciseID)))
            }
            unit = stored.displayUnit
            isConfigured = stored.dashboardExerciseIDs != nil
            selection = chosen
            tiles = built
            failure = nil
        } catch {
            failure = String(describing: error)
        }
        hasLoaded = true
    }

    /// Stores which exercises are tiled (`FR-1.9.1`), then redraws them.
    ///
    /// **An empty selection is stored rather than treated as a clearing.** "No tiles" is a choice the
    /// picker can express, and writing `nil` for it would hand the user the three defaults back on
    /// the next launch — see ``RepositoryInterface/UserSettings/dashboardExerciseIDs``.
    ///
    /// A failed write leaves the screen showing what it already showed, with the failure beside the
    /// control that issued it — the rule every write on this app's screens follows.
    ///
    /// - Parameter exerciseIDs: The exercises to tile, in the order to draw them.
    func save(_ exerciseIDs: [UUID]) async {
        do {
            let stored = try await settings.settings()
            try await settings.save(stored.tiling(exerciseIDs))
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
            return
        }
        await load()
    }

    /// Re-reads whenever a set logged anywhere, or a formula chosen in Settings, moves a number
    /// (`TR-1.5`, `FR-1.7.3`).
    ///
    /// **Every announcement is acted on, including one for an exercise that is not tiled.** Deciding
    /// otherwise would mean the tiles going stale exactly when the picker changes what is tiled, and
    /// the read is three estimates.
    func observeChanges() async {
        for await _ in await records.changes() {
            await load()
        }
    }
}
