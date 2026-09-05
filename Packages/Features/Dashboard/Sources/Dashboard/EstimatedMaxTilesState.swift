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

    /// The estimate, or the reason there is none.
    let estimate: EstimatedMax

    /// The training max in force today, or `nil` where this exercise has never had one
    /// (`FR-15.1.8`).
    ///
    /// **`nil` is the common case and it draws nothing** — no zero and no dash. Nothing writes a
    /// training max until the exercise detail's own section does, so a tile that reported an absence
    /// would report it on every tile of every first launch.
    let trainingMax: Weight?

    /// See `Identifiable`.
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

    /// Which exercises are tiled, as stored or as defaulted.
    ///
    /// **It is what was asked for, where ``tiles`` is what could be built** — the two differ by
    /// every identifier the catalogue could not resolve, which is the distinction a deleted exercise
    /// makes and the reason both are kept. ``TiledExerciseSelectionState`` resolves the same
    /// selection for itself rather than reading this: the picker is a separate screen with a
    /// separate read, and a stale copy handed across is the shape that write is trying to avoid.
    private(set) var selection: [UUID] = []

    /// Whether the user has ever chosen. `false` means ``selection`` is ``DashboardDefaults``'.
    private(set) var isConfigured = false

    /// Whether the first read has answered. See ``DerivedValues/ExerciseRecordsState``.
    private(set) var hasLoaded = false

    /// Why the read failed, or `nil`. A retry may work.
    private(set) var failure: String?

    /// The unit the loads are shown in (`G-3.1`) — read here rather than by each tile, since one
    /// settings read already answers it.
    private(set) var unit: MassUnit = .kilograms

    /// The app's one recompute actor (`TR-1.6`).
    private let records: PersonalRecordRecomputer

    /// The catalogue: which exercises the defaults resolve to, and what each tile is called.
    private let catalogue: any ExerciseRepository

    /// The settings row, which carries both the selection and the display unit.
    private let settings: any SettingsRepository

    /// Where `FR-15.1.8`'s number under each tile comes from.
    private let trainingMaxes: any TrainingMaxRepository

    /// What "today" is when the training max in force is resolved — injectable, so a test can
    /// assert a date rather than wait for one.
    private let now: @Sendable () -> Date

    /// Which of an exercise's two names a tile carries (`FR-1.14.2`).
    ///
    /// A tile's name is a string built by ``load()``, not a record a view can resolve for itself —
    /// the view sets this, on ``RepositoryInterface/ExerciseNameLanguage``'s rule.
    var nameLanguage: ExerciseNameLanguage = .english

    /// Builds the state over the three things a tile is made of.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor.
    ///   - catalogue: The exercises.
    ///   - settings: The settings row (`FR-1.9.1`'s selection, `G-3.1`'s unit).
    ///   - trainingMaxes: Where `FR-15.1.8`'s number under each tile is stored.
    ///   - now: What "today" is when the number in force is resolved.
    init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        trainingMaxes: any TrainingMaxRepository,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.records = records
        self.catalogue = catalogue
        self.settings = settings
        self.trainingMaxes = trainingMaxes
        self.now = now
    }

    /// Reads the selection, resolves it against the catalogue and values every tile.
    ///
    /// **The estimates are read one exercise at a time and there are three of them**, which is the
    /// bound that keeps this off `NFR-1.6`'s slow path: the number of reads is the number of tiles
    /// the user chose, never the size of the catalogue. `FR-15.1.8`'s training max doubles that
    /// count and not its order: it is a lookup over one exercise's history, not a walk of its sets.
    func load() async {
        do {
            let today = now()
            let stored = try await settings.settings()
            let exercises = try await catalogue.exercises(includingDeleted: false)
            let chosen = stored.dashboardExerciseIDs ?? DashboardDefaults.exerciseIDs(in: exercises)
            let named = Dictionary(
                exercises.map { ($0.id, $0.displayName(in: nameLanguage)) }
            ) { first, _ in first }
            var built: [EstimatedMaxTile] = []
            for exerciseID in chosen {
                guard let name = named[exerciseID] else { continue }
                built.append(
                    EstimatedMaxTile(
                        exerciseID: exerciseID,
                        name: name,
                        estimate: try await records.estimatedMax(forExerciseID: exerciseID),
                        trainingMax: try await trainingMaxes.trainingMax(
                            forExerciseID: exerciseID, on: today)?.newWeight))
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

    /// Re-reads whenever a set logged anywhere, or a formula chosen in Settings, moves a number
    /// (`TR-1.5`, `FR-1.7.3`).
    ///
    /// **Every announcement is acted on, including one for an exercise that is not tiled.** Deciding
    /// otherwise would mean the tiles going stale exactly when the picker changes what is tiled, and
    /// the read is three estimates.
    ///
    /// **This is also how a training max typed on the exercise detail screen reaches the tile
    /// without the tab being revisited** (`TR-1.5`) — see
    /// ``DerivedValues/PersonalRecordRecomputer/trainingMaxDidChange(forExerciseID:)``.
    func observeChanges() async {
        for await _ in await records.changes() {
            await load()
        }
    }
}
