import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// What this week held, in the two facts `FR-1.9.5` names.
struct WeekSummary: Sendable, Equatable {
    /// How many workouts were trained — sessions holding at least one working set.
    ///
    /// **A session with nothing performed in it is not a workout here.** The population is
    /// ``DerivedValues/Tonnage/counts(_:)``, the same one the volume beside it is summed over, so a
    /// session opened and abandoned does not raise the count while contributing nothing to the load.
    /// A workout still in progress *does* count, on `LastWorkoutState`'s rule: it is training that
    /// happened this week whether or not it has been closed.
    let workoutCount: Int

    /// The load moved, over the sets ``DerivedValues/Tonnage`` can weigh.
    let tonnage: Weight
}

/// `FR-1.9.5`'s week, and `FR-1.13.2`'s "has this install ever been used" — one read answering both.
///
/// **One unbounded session read, not two.** Whether anything has *ever* been logged cannot be
/// answered from a bounded range, and the week is a filter over what that read already returned, so
/// asking the store twice would put a second unbounded walk on the screen the app launches into for
/// an answer it already has. `NFR-1.6`'s formal number is `T-1.83`'s; this is one caller, not two.
///
/// **The two answers cannot disagree**, which is the other half of folding them together: a screen
/// that decided "first launch" from one read and drew a week summary from another could show a
/// guided empty state above a card reporting three workouts.
@Observable
final class WeekSummaryState {
    /// This week's two numbers, or `nil` until the first read answers.
    private(set) var summary: WeekSummary?

    /// Whether any session has ever been logged — `FR-1.13.2`'s whole question.
    ///
    /// **Sessions, not working sets.** A lifter who opened a workout and logged nothing is not on
    /// first launch: they have been to Train, and the last-workout card has something to offer them.
    private(set) var hasEverTrained = false

    /// Whether the first read has answered.
    private(set) var hasLoaded = false

    /// Why the read failed, or `nil`. A retry may work.
    private(set) var failure: String?

    /// The sessions, their entries and their sets.
    private let workouts: any WorkoutRepository

    /// Which days this week holds — the user's own, so `firstWeekday` is theirs (`G-3.4`).
    private let calendar: Calendar

    /// What "now" is. Injected so a test can pin a week rather than chase the one it runs in.
    private let now: () -> Date

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - workouts: The sessions and what is under them.
    ///   - calendar: Which days this week holds. Defaults to the user's.
    ///   - now: What day it is. Defaults to the clock.
    init(
        workouts: any WorkoutRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.workouts = workouts
        self.calendar = calendar
        self.now = now
    }

    /// Reads every session, then weighs the ones inside this week.
    ///
    /// **The set reads are bounded to this week's sessions**, which is what keeps the walk small: a
    /// year of training is one session read plus the entries and sets of at most a handful of days.
    ///
    /// A session whose entries or sets cannot be read fails the whole summary rather than being
    /// silently omitted — a volume missing one exercise is a wrong number, not a partial one.
    func load() async {
        do {
            let sessions = try await workouts.sessions(
                in: Date.distantPast...Date.distantFuture, includingDeleted: false)
            hasEverTrained = !sessions.isEmpty
            summary = try await weigh(sessions.filter(isThisWeek))
            failure = nil
        } catch {
            failure = String(describing: error)
        }
        hasLoaded = true
    }

    /// Whether `session`'s training day falls in the week being reported.
    ///
    /// **The training day, not when the row was written** — `FR-1.2.1` backdates, so a session
    /// entered today for last Tuesday belongs to last week and a week summary that read `createdAt`
    /// would credit it to this one.
    private func isThisWeek(_ session: WorkoutSession) -> Bool {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now()) else { return false }
        return week.contains(session.date)
    }

    /// The count and the load over `sessions`.
    ///
    /// - Parameter sessions: The week's sessions.
    /// - Returns: What they hold.
    private func weigh(_ sessions: [WorkoutSession]) async throws -> WeekSummary {
        var workoutCount = 0
        var tonnage = Weight.zero
        for session in sessions {
            var didTrain = false
            let entries = try await workouts.entries(
                forSessionID: session.id, includingDeleted: false)
            for entry in entries {
                let sets = try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
                if sets.contains(where: Tonnage.counts) { didTrain = true }
                tonnage += Tonnage.of(sets)
            }
            if didTrain { workoutCount += 1 }
        }
        return WeekSummary(workoutCount: workoutCount, tonnage: tonnage)
    }
}
