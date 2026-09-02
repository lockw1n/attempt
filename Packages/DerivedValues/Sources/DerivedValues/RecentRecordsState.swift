import Foundation
import Observation
import PowerliftingCore
import RepositoryInterface

/// What `FR-1.6.5`'s global feed looks like to a screen, kept current without polling (`TR-1.5`).
///
/// **``ExerciseRecordsState``'s cross-exercise sibling, and it is a second type rather than a mode
/// of that one.** The two answer different questions from different reads: that one is about one
/// exercise and may recompute it, this one reads the whole cache and never recomputes anything (see
/// ``PersonalRecordRecomputer/recentRecords(limit:)``). Folding them together would put a branch in
/// every property.
///
/// **One read and one join, and only the read has a diagnostic.** The records come from the cache;
/// the names come from the catalogue and are best-effort, on
/// ``ExerciseRecordsState/sourceSessions``' rule — a feed that reported itself unreadable because a
/// name would not resolve would name the wrong thing as broken.
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

    /// Why the last read failed, as the error's description, or `nil`. A **diagnostic**, not copy
    /// (`G-3.4`).
    public private(set) var failure: String?

    /// How many entries this feed draws.
    @ObservationIgnored public let limit: Int

    /// Where the records come from.
    @ObservationIgnored private let recomputer: PersonalRecordRecomputer

    /// Where the names come from.
    @ObservationIgnored private let catalogue: any ExerciseRepository

    /// The read a publish belongs to — ``ExerciseRecordsState/read``'s gate, for its reason.
    @ObservationIgnored private var read = 0

    /// Builds the feed's state.
    ///
    /// - Parameters:
    ///   - recomputer: The app's one recomputer, so a set logged anywhere reaches this.
    ///   - catalogue: The exercises, for the name on each row.
    ///   - limit: How many entries to draw — ``cardLimit`` or ``listLimit``.
    public init(
        recomputer: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        limit: Int
    ) {
        self.recomputer = recomputer
        self.catalogue = catalogue
        self.limit = limit
    }

    /// Reloads the feed and the names on it.
    ///
    /// **The names are resolved after the records and only for the ones drawn.** A catalogue read
    /// that failed leaves the feed on screen without them, which is the best-effort half this type's
    /// note describes.
    public func load() async {
        let token = beginRead()
        do {
            let loaded = try await recomputer.recentRecords(limit: limit)
            guard isCurrent(token) else { return }
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

    /// Keeps this current until cancelled (`TR-1.5`).
    ///
    /// **Every exercise's change is taken, which is the opposite of ``ExerciseRecordsState``'s
    /// filter and is the same rule underneath**: a subscriber reloads for a change that can move
    /// what it draws, and this draws all of them. A formula change is still ignored — a rep max
    /// reads no setting, so nothing a picker does can move one.
    public func observeChanges() async {
        for await change in await recomputer.changes() {
            switch change {
            case .exercise:
                await load()
            case .everyExercise:
                continue
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
