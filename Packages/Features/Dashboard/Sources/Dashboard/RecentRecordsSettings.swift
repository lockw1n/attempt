import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// One scheme the feed could be narrowed to, and whether it is (`FR-16.3.2`).
struct RecentRecordsSchemeChoice: Identifiable, Sendable, Equatable {
    /// The cell.
    let scheme: RecordScheme

    /// Whether the lifter has ticked it.
    let isChosen: Bool

    /// See `Identifiable`. A scheme is its own identity — the list holds each cell once.
    var id: RecordScheme { scheme }
}

/// `FR-16.3`'s configuration screen: what the recent-PR feed reports on.
///
/// **Four controls over one row, written straight through on every change** (`NFR-1.8`), which is
/// `TiledExerciseSelectionState`'s posture and for its reason: the feed behind this screen is
/// already showing the result, so there is no Save button to forget. Each write re-reads, because
/// three of the four controls change what the *other* controls offer — widening the scope changes
/// which schemes are available to choose among.
///
/// **The candidate schemes come from the records, not from the table.** `FR-16.2.1`'s table is sixty
/// cells and a checklist of sixty is not a control; what the feed can actually draw is the distinct
/// *maximal* scheme of each run in scope (`FR-16.3.2`), which is a short list of the shapes this
/// lifter trains. A cell already chosen stays listed even where no record carries it any more, on
/// `SettingsOptions`' rule: a picker whose selection is absent from its own options cannot be
/// un-ticked.
@Observable
final class RecentRecordsSettingsState {
    /// The row every control reads its selection from, or `nil` before the first read answers.
    private(set) var settings: UserSettings?

    /// Every exercise the `.chosen` scope can name, ordered by name.
    ///
    /// Read whatever the scope is, so switching to `.chosen` does not land on an empty screen while
    /// a second read runs.
    private(set) var exerciseChoices: [TiledExerciseChoice] = []

    /// The schemes in scope, and which are ticked.
    private(set) var schemeChoices: [RecentRecordsSchemeChoice] = []

    /// Whether the first read has answered.
    private(set) var hasLoaded = false

    /// Why the read failed, or `nil`.
    private(set) var failure: String?

    /// Why the last change could not be stored, or `nil`. Nothing changed when it is set.
    private(set) var writeFailure: String?

    /// Which of an exercise's two names a row shows, and orders by (`FR-1.14.2`).
    var nameLanguage: ExerciseNameLanguage = .english

    /// Where the row lives.
    @ObservationIgnored private let settingsRepository: any SettingsRepository

    /// The exercises to choose among, and what `FR-1.9.1`'s default scope resolves against.
    @ObservationIgnored private let catalogue: any ExerciseRepository

    /// Where the candidate schemes are read from, and what is told that the row moved.
    @ObservationIgnored private let recomputer: PersonalRecordRecomputer

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - settings: Where the configuration is stored.
    ///   - catalogue: The exercises to choose among.
    ///   - records: The app's one recompute actor — the candidate schemes, and the announcement that
    ///     tells the feed to re-read (`TR-1.5`).
    init(
        settings: any SettingsRepository,
        catalogue: any ExerciseRepository,
        records: PersonalRecordRecomputer
    ) {
        self.settingsRepository = settings
        self.catalogue = catalogue
        self.recomputer = records
    }

    /// Reads the row, the catalogue and the schemes the current scope offers.
    ///
    /// **A fresh read retires ``writeFailure``**, `TiledExerciseSelectionState/load()`'s rule: a
    /// failed change is reported beside the controls it did not move, and those controls are exactly
    /// what this replaces.
    func load() async {
        writeFailure = nil
        do {
            let stored = try await settingsRepository.settings()
            let exercises = try await catalogue.exercises(includingDeleted: false)
            let chosen = Set(stored.recentRecordsExerciseIDs ?? [])
            let scope = await RecentRecordsFilter.scope(of: stored) {
                DashboardDefaults.exerciseIDs(in: exercises)
            }
            settings = stored
            exerciseChoices = ExerciseDisplayOrder.sorted(exercises, in: nameLanguage).map {
                TiledExerciseChoice(
                    exerciseID: $0.id,
                    name: $0.displayName(in: nameLanguage),
                    isTiled: chosen.contains($0.id))
            }
            schemeChoices = try await schemes(inScope: scope, chosen: stored.recentRecordsSchemes)
            failure = nil
        } catch {
            failure = String(describing: error)
        }
        hasLoaded = true
    }

    /// Moves one field on the stored row and re-reads (`FR-16.3.1`, `FR-16.3.2`, `FR-16.3.4`).
    ///
    /// **It re-reads the row before writing rather than saving the copy on screen.** A control here
    /// changes what the other controls offer, so the row this screen holds can be one read behind
    /// its own last write — and `UserSettings`' own note calls a save assembled from a screen's
    /// knowledge the stale-write shape.
    ///
    /// - Parameter change: What to move.
    func apply(_ change: (inout UserSettings) -> Void) async {
        do {
            var stored = try await settingsRepository.settings()
            change(&stored)
            try await settingsRepository.save(stored)
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
            return
        }
        // The feed is on another screen and is not revisited on the way back (`TR-1.5`).
        await recomputer.recentRecordsPreferencesDidChange()
        await load()
    }

    /// Adds or removes one exercise from the `.chosen` list (`FR-16.3.1`).
    ///
    /// An added exercise goes to the end, on `TiledExerciseSelectionState/toggle(_:)`'s rule.
    ///
    /// - Parameter exerciseID: The exercise to toggle.
    func toggleExercise(_ exerciseID: UUID) async {
        await apply { stored in
            let current = stored.recentRecordsExerciseIDs ?? []
            stored.recentRecordsExerciseIDs =
                current.contains(exerciseID)
                ? current.filter { $0 != exerciseID } : current + [exerciseID]
        }
    }

    /// Adds or removes one scheme from the chosen list (`FR-16.3.2`).
    ///
    /// - Parameter scheme: The cell to toggle.
    func toggleScheme(_ scheme: RecordScheme) async {
        let offered = schemeChoices.map(\.scheme)
        await apply { stored in
            let current = stored.recentRecordsSchemes.chosenSchemes ?? offered
            stored.recentRecordsSchemes = .chosen(
                current.contains(scheme)
                    ? current.filter { $0 != scheme } : current + [scheme])
        }
    }

    /// Switches between derived and chosen schemes (`FR-16.3.2`).
    ///
    /// **Turning the chosen list *on* seeds it with everything on offer, not with nothing.** The
    /// list is a narrowing, and a switch whose first effect is to empty the feed reads as the
    /// control being broken rather than as a starting point — so the feed does not move until the
    /// lifter unticks something, which is the tap that means it.
    ///
    /// - Parameter isDerived: Whether the schemes follow the training log.
    func setSchemesDerived(_ isDerived: Bool) async {
        let offered = schemeChoices.map(\.scheme)
        await apply { stored in
            stored.recentRecordsSchemes = isDerived ? .derived : .chosen(offered)
        }
    }

    /// The schemes the scope's records actually carry, plus any already chosen.
    ///
    /// Read at the list limit rather than the card's: this is the set of shapes the *full* feed can
    /// draw, and a control offering only what fits on the dashboard would hide cells the screen
    /// behind it shows.
    private func schemes(
        inScope scope: Set<UUID>?, chosen: RecentRecordsSchemes
    ) async throws -> [RecentRecordsSchemeChoice] {
        let available = try await recomputer.recentRecords(
            limit: RecentRecordsState.listLimit, filter: .scoped(to: scope))
        let ticked = chosen.chosenSchemes
        let offered = Set(available.map(\.scheme)).union(ticked ?? [])
        // A derived list ticks nothing, and the ticks are not drawn under it either: the cells it
        // shows are the log's answer rather than the lifter's.
        return offered.sorted().map {
            RecentRecordsSchemeChoice(scheme: $0, isChosen: ticked?.contains($0) ?? false)
        }
    }
}
