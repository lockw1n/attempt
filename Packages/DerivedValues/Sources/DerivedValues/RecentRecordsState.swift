import Foundation
import Observation
import PowerliftingCore
import RepositoryInterface

/// What `FR-1.6.5`'s global feed looks like to a screen, kept current without polling (`TR-1.5`).
///
/// **``ExerciseRecordsState``'s cross-exercise sibling, and it is a second type rather than a mode
/// of that one.** The two answer different questions from different reads: that one is about one
/// exercise and may recompute it, this one reads the whole cache and never recomputes anything (see
/// ``PersonalRecordRecomputer/recentRecords(limit:filter:)``). Folding them together would put a branch in
/// every property.
///
/// **One read and one join, and only the read has a diagnostic.** The records come from the cache;
/// the names come from the catalogue and are best-effort, on
/// ``ExerciseRecordsState/sourceSessions``' rule — a feed that reported itself unreadable because a
/// name would not resolve would name the wrong thing as broken.
///
/// **The settings row is not best-effort, and that is `FR-16.3`'s doing.** What the row carries is
/// no longer only the unit the loads read in: it decides which records the feed contains, so a
/// settings read that failed cannot be swallowed into an unfiltered feed presented as a configured
/// one. It is part of the read that has the diagnostic.
@MainActor
@Observable
public final class RecentRecordsState {
    /// How many entries the dashboard's card draws (`FR-1.9.3`).
    public static let cardLimit = 5

    /// How many the full list behind it draws (`FR-1.6.5`).
    ///
    /// **Capped, because this is a feed rather than an archive.** Every record an exercise holds
    /// stays readable on its own detail screen (`FR-1.6.2`), so nothing is put out of reach by a
    /// bound — and an unbounded list is one row per PR-setting set for the lifetime of the log.
    public static let listLimit = 50

    /// The feed, newest first. Empty before anything has loaded and when the cache holds nothing
    /// this build computed — ``hasLoaded`` is what separates those.
    public private(set) var records: [RecentRecord] = []

    /// Each record's exercise, by name (`G-3.4`: the name is the catalogue's copy, not this
    /// module's).
    ///
    /// **A separate map rather than a field on ``RecentRecord``**, on
    /// ``ExerciseRecordsState/sourceSessions``' rule: a name is a catalogue row's, and a copy
    /// carried on a derived value is a second source of truth for it (`G-1.4`).
    ///
    /// An exercise missing from here is a row that names no exercise, not a row that has none.
    public private(set) var exerciseNames: [UUID: String] = [:]

    /// Which of an exercise's two names the feed's rows carry (`FR-1.14.2`).
    ///
    /// ``exerciseNames`` is a lookup this state builds, so a row cannot resolve one for itself —
    /// the view sets this, on ``RepositoryInterface/ExerciseNameLanguage``'s rule.
    public var nameLanguage: ExerciseNameLanguage = .english

    /// Whether ``load()`` has ever completed. A feed with nothing in it and one nothing has looked
    /// at are both an empty ``records``, and a screen says opposite things about them.
    public private(set) var hasLoaded = false

    /// Whether the last read ran under a filter that could have removed something (`FR-16.3`).
    ///
    /// **All three narrowings, not the scope alone.** An empty feed offers the wider one
    /// (`FR-16.3.4`), and that offer is only honest where something was actually narrowed — but a
    /// scope of every exercise is not on its own the widest the feed goes: `FR-16.3.4`'s own
    /// default hides baselines, and `FR-16.3.2`'s chosen list hides cells. A screen reading the
    /// scope alone tells a lifter whose records are all first-time ones to go and log a working
    /// set, which is the dead end the offer exists to remove.
    ///
    /// ``RepositoryInterface/RecentRecordsSchemes/derived`` does not count: it is the
    /// un-configured value, and what it drops it drops from the training log rather than from a
    /// choice the lifter made.
    /// `true` before the first read, because an unconfigured row is narrowed — `FR-16.3.1` scopes
    /// it to the dashboard lifts and `FR-16.3.4` hides baselines. Nothing reads it until
    /// ``hasLoaded``, so this is the safe answer rather than the load-bearing one.
    public private(set) var isNarrowed = true

    /// The unit the loads on these rows are shown in (`G-3.1`).
    ///
    /// **Read here rather than by the row, now that the same row decides what the feed contains.**
    /// A record reads no setting — which is what lets `TR-0.3.9` cache it — but the *feed* reads
    /// three, so the settings row is fetched by this read anyway and a second fetch for the unit
    /// would be a second answer to the same question.
    public private(set) var displayUnit: MassUnit = .kilograms

    /// Why the last read failed, as the error's description, or `nil`. A **diagnostic**, not copy
    /// (`G-3.4`).
    public private(set) var failure: String?

    /// How many entries this feed draws.
    @ObservationIgnored public let limit: Int

    /// Where the records come from.
    @ObservationIgnored private let recomputer: PersonalRecordRecomputer

    /// Where the names come from, and where `FR-16.3.1`'s default scope is resolved against.
    @ObservationIgnored private let catalogue: any ExerciseRepository

    /// The settings row: the scope, the schemes, the baseline flag and the unit.
    @ObservationIgnored private let settings: any SettingsRepository

    /// `FR-1.9.1`'s selection for a lifter who has never made one.
    ///
    /// **Injected rather than computed here**, because it is a rule about the catalogue — the three
    /// competition lifts resolved by movement, equipment and name against the rows actually
    /// installed — and that rule belongs to the dashboard feature one layer up. This module would
    /// otherwise hold a second copy of it.
    @ObservationIgnored private let defaultDashboardExerciseIDs: ([Exercise]) -> [UUID]

    /// The read a publish belongs to — ``ExerciseRecordsState/read``'s gate, for its reason.
    @ObservationIgnored private var read = 0

    /// Builds the feed's state.
    ///
    /// - Parameters:
    ///   - recomputer: The app's one recomputer, so a set logged anywhere reaches this.
    ///   - catalogue: The exercises, for the name on each row and for the default scope.
    ///   - settings: Where `FR-16.3`'s configuration and `G-3.1`'s unit live.
    ///   - limit: How many entries to draw — ``cardLimit`` or ``listLimit``.
    ///   - defaultDashboardExerciseIDs: `FR-1.9.1`'s selection where the lifter has made none.
    public init(
        recomputer: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        limit: Int,
        defaultDashboardExerciseIDs: @escaping ([Exercise]) -> [UUID]
    ) {
        self.recomputer = recomputer
        self.catalogue = catalogue
        self.settings = settings
        self.limit = limit
        self.defaultDashboardExerciseIDs = defaultDashboardExerciseIDs
    }

    /// Reloads the feed and the names on it.
    ///
    /// **The names are resolved after the records and only for the ones drawn.** A catalogue read
    /// that failed leaves the feed on screen without them, which is the best-effort half this type's
    /// note describes.
    public func load() async {
        let token = beginRead()
        do {
            let stored = try await settings.settings()
            let filter = try await resolvedFilter(stored)
            let loaded = try await recomputer.recentRecords(limit: limit, filter: filter)
            guard isCurrent(token) else { return }
            isNarrowed = Self.narrows(stored)
            displayUnit = stored.displayUnit
            records = loaded
            hasLoaded = true
            failure = nil
        } catch {
            guard isCurrent(token) else { return }
            hasLoaded = true
            failure = String(describing: error)
            return
        }
        await loadNames(token)
    }

    /// `FR-16.3.4`'s offer taken: relaxes every narrowing and re-reads.
    ///
    /// **All three, because the offer is one button and the feed is empty under whichever of them
    /// did it.** A widening that moved the scope and left baselines hidden would answer the offer
    /// with the same empty feed and no second offer to make.
    ///
    /// **It writes the settings rather than reading past them for one screenful.** A lifter who
    /// accepts is saying the narrowing was wrong — one that lasted until the screen went away would
    /// put them back where they started on the next launch, with no way to tell that they had
    /// already answered.
    ///
    /// A write that fails leaves ``failure`` set and the feed as it was; nothing changed, and the
    /// button is still there.
    public func showEverything() async {
        do {
            var stored = try await settings.settings()
            stored.recentRecordsScope = .everyExercise
            stored.recentRecordsShowsBaselines = true
            stored.recentRecordsSchemes = .derived
            try await settings.save(stored)
        } catch {
            failure = String(describing: error)
            return
        }
        await recomputer.recentRecordsPreferencesDidChange()
        await load()
    }

    /// Whether `stored` narrows the feed at all — the inverse of what ``showEverything()`` writes.
    ///
    /// - Parameter stored: The settings row.
    /// - Returns: Whether anything could have been removed.
    private static func narrows(_ stored: UserSettings) -> Bool {
        stored.recentRecordsScope != .everyExercise
            || !stored.recentRecordsShowsBaselines
            || stored.recentRecordsSchemes != .derived
    }

    /// What `stored` narrows the feed to, with `FR-16.3.1`'s scope resolved to identifiers.
    ///
    /// The catalogue is read only where it has to be: a lifter who has configured their dashboard
    /// already carries the identifiers on the row.
    private func resolvedFilter(_ stored: UserSettings) async throws -> RecentRecordsFilter {
        let exerciseIDs = try await RecentRecordsFilter.scope(of: stored) {
            defaultDashboardExerciseIDs(try await catalogue.exercises(includingDeleted: false))
        }
        return RecentRecordsFilter(
            exerciseIDs: exerciseIDs,
            schemes: stored.recentRecordsSchemes,
            showsBaselines: stored.recentRecordsShowsBaselines)
    }

    /// Keeps this current until cancelled (`TR-1.5`).
    ///
    /// **Every exercise's change is taken, which is the opposite of ``ExerciseRecordsState``'s
    /// filter and is the same rule underneath**: a subscriber reloads for a change that can move
    /// what it draws, and this draws all of them.
    ///
    /// **A settings change is taken too, and it did not used to be.** The old reasoning was that a
    /// rep max reads no setting, so nothing a picker does can move one — true of the records and no
    /// longer true of the feed, which reads three settings since `FR-16.3`. That is what carries a
    /// change made on `settings.recentRecords` back to this screen without it being revisited
    /// (`TR-1.5`); the cost is that a formula change, which still moves nothing here, reloads it.
    public func observeChanges() async {
        for await change in await recomputer.changes() {
            switch change {
            case .exercise, .everyExercise:
                await load()
            }
        }
    }

    /// Resolves the drawn rows' exercise names, for the ones the catalogue answers for.
    ///
    /// Archived and soft-deleted rows are read: a record outlives the retirement of the exercise it
    /// was set on, and a feed entry with no name is worse than one naming a retired movement.
    private func loadNames(_ token: Int) async {
        let wanted = Set(records.map(\.exerciseID))
        guard !wanted.isEmpty else {
            exerciseNames = [:]
            return
        }
        let catalogued = (try? await catalogue.exercises(includingDeleted: true)) ?? []
        guard isCurrent(token) else { return }
        exerciseNames =
            catalogued
            .filter { wanted.contains($0.id) }
            .reduce(into: [:]) { names, exercise in
                names[exercise.id] = exercise.displayName(in: nameLanguage)
            }
    }

    /// Claims the next read's token. Taken before the first `await`.
    private func beginRead() -> Int {
        read += 1
        return read
    }

    /// Whether the read `token` belongs to is still the one the screen is waiting for.
    private func isCurrent(_ token: Int) -> Bool {
        token == read && !Task.isCancelled
    }
}
