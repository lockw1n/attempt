import Foundation
import RepositoryInterface

/// The last workout, as `FR-1.9.2`'s card reports it.
///
/// **One value built by one read and never re-read while it is on screen**, on `SessionSummary`'s
/// rule: a card holding a repository would make every redraw a read of a session's sets.
struct LastWorkoutSummary: Sendable, Equatable {
    /// The session this summarises — what "repeat" copies, and what "resume" opens.
    let sessionID: UUID

    /// The training day (`FR-1.2.1` backdates, so this is not when it was entered).
    let date: Date

    /// Whether it is still in progress, which is what decides between `FR-1.9.2`'s two actions.
    let isInProgress: Bool

    /// What was trained, in the order it was performed, each exercise named once.
    let exerciseNames: [String]

    /// How many working sets it holds — completed, and not warmups (`G-1.8`).
    let workingSetCount: Int

    /// Whether it has ended, and if not which kind of open it is (`FR-16.4.3`).
    ///
    /// **A second reading of ``isInProgress`` rather than a replacement for it.** That flag decides
    /// between `FR-1.9.2`'s two commands — resume or repeat — and both open workouts resume; this
    /// says which word the card puts where a finished workout shows its set count.
    var lifecycle: SessionLifecycle = .finished
}

/// `FR-1.9.2`'s read: the workout in progress, or the most recent finished one.
///
/// **"In progress" is looked for the way `ActiveSessionStore.resume()` looks for it** — the first
/// session with no end, over every session rather than only the newest — so this card and Train's
/// root can never disagree about whether a workout is open. That matters beyond tidiness: it is what
/// stops "repeat" being offered while an older backdated session is still open, which would leave two
/// workouts in progress.
@Observable
final class LastWorkoutState {
    /// The workout to report, or `nil` when nothing has been logged.
    private(set) var summary: LastWorkoutSummary?

    /// Whether the first read has answered.
    private(set) var hasLoaded = false

    /// Why the read failed, or `nil`. A retry may work.
    private(set) var failure: String?

    /// Whether the last repeat could not be started. The card is unchanged either way.
    private(set) var repeatDidFail = false

    /// Which of an exercise's two names the card lists (`FR-1.14.2`).
    ///
    /// The card's names are strings this state builds, and it de-duplicates on them — the view sets
    /// this, on ``RepositoryInterface/ExerciseNameLanguage``'s rule.
    var nameLanguage: ExerciseNameLanguage = .english

    /// The sessions, their entries and their sets.
    private let workouts: any WorkoutRepository

    /// The catalogue, for the names of what was trained.
    private let catalogue: any ExerciseRepository

    /// The day an open workout is read against (`FR-16.4.3`).
    private let today: Date

    /// The calendar the two days are compared in (`G-3.4`).
    private let calendar: Calendar

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - workouts: The sessions and what is under them.
    ///   - catalogue: Where the exercise names come from.
    ///   - today: The day an open workout is read against.
    ///   - calendar: The calendar the two days are compared in.
    init(
        workouts: any WorkoutRepository,
        catalogue: any ExerciseRepository,
        today: Date = .now,
        calendar: Calendar = .current
    ) {
        self.workouts = workouts
        self.catalogue = catalogue
        self.today = today
        self.calendar = calendar
    }

    /// Reads the workout to report and summarises it.
    ///
    /// **The set read is one session's.** The *session* read is not bounded and cannot be: an open
    /// workout may be backdated behind any number of finished ones, so finding it means looking at
    /// them all — ``Logging/ActiveSessionStore/resume()`` reads the same unbounded range for the
    /// same reason, and this card agreeing with Train's root is the point. `NFR-1.6`'s formal
    /// number is `T-1.83`'s, and this is a second caller for it to weigh.
    ///
    /// **A fresh read retires ``repeatDidFail``**, on `TrainingHomeView`'s rule: a failure left
    /// standing across a read would be drawn beside a card that has since changed under it, and a
    /// user who leaves Home and returns would be told again about a write that is no longer what
    /// the screen is showing.
    func load() async {
        repeatDidFail = false
        do {
            let sessions = try await workouts.sessions(
                in: Date.distantPast...Date.distantFuture, includingDeleted: false)
            guard let session = sessions.first(where: { $0.endedAt == nil }) ?? sessions.first else {
                summary = nil
                failure = nil
                hasLoaded = true
                return
            }
            summary = try await summarise(session)
            failure = nil
        } catch {
            failure = String(describing: error)
        }
        hasLoaded = true
    }

    /// Records what a repeat reported.
    ///
    /// **The command is not this state's**, because starting a workout is `Logging`'s and no feature
    /// package depends on another (`TR-1.3`); what belongs here is the failure a screen has to draw.
    ///
    /// - Parameter didStart: Whether a workout is now in progress.
    func repeatDidFinish(started didStart: Bool) {
        repeatDidFail = !didStart
    }

    /// One session as the card reads it.
    ///
    /// An entry whose exercise the catalogue cannot name is counted and left unnamed rather than
    /// dropped: the sets under it were still performed.
    private func summarise(_ session: WorkoutSession) async throws -> LastWorkoutSummary {
        let entries = try await workouts.entries(forSessionID: session.id, includingDeleted: false)
            .sorted { $0.order < $1.order }
        let named = Dictionary(
            try await catalogue.exercises(includingDeleted: true)
                .map { ($0.id, $0.displayName(in: nameLanguage)) }
        ) { first, _ in first }
        var names: [String] = []
        var workingSets = 0
        for entry in entries {
            if let name = named[entry.exerciseID], !names.contains(name) { names.append(name) }
            workingSets += try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
                .count { $0.isCompleted && !$0.isWarmup }
        }
        return LastWorkoutSummary(
            sessionID: session.id,
            date: session.date,
            isInProgress: session.endedAt == nil,
            exerciseNames: names,
            workingSetCount: workingSets,
            lifecycle: session.lifecycle(on: today, calendar: calendar))
    }
}
