import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// What one week held, in the two facts `FR-1.9.5` names.
struct WeekSummary: Sendable, Equatable {
    /// How many workouts were trained — sessions holding at least one working set.
    ///
    /// **A session with nothing performed in it is not a workout here.** The population is
    /// ``DerivedValues/Tonnage/counts(_:)``, the same one the volume beside it is summed over, so a
    /// session opened and abandoned does not raise the count while contributing nothing to the load.
    /// A workout still in progress *does* count: it is training that happened this week whether or
    /// not it has been closed.
    let workoutCount: Int

    /// The load moved, over the sets ``DerivedValues/Tonnage`` can weigh.
    let tonnage: Weight

    /// A week with nothing trained in it.
    static let empty = WeekSummary(workoutCount: 0, tonnage: .zero)
}

/// The three weeks the card reads (`FR-18.9.2`, `FR-18.9.3`): the one in progress, the last
/// completed one, and the one before that — which is only here so that last week has something to
/// be compared with.
struct WeekSummaries: Sendable, Equatable {
    /// The week in progress, so far.
    let thisWeek: WeekSummary

    /// The last completed week.
    let lastWeek: WeekSummary

    /// The week before that. Never drawn; it is what ``lastWeekChange`` is measured against.
    let weekBefore: WeekSummary

    /// How last week's volume moved against the week before it, or `nil` where there is nothing
    /// to compare (`FR-18.9.3`).
    ///
    /// **The change compares the last two *completed* weeks, never this week against last.** A
    /// part-week against a whole one reads as a loss from Monday to Thursday, so the week in
    /// progress carries no change until it is over — which is when it becomes ``lastWeek``.
    ///
    /// **`nil` when either side has no volume.** A week of bodyweight work has a real workout
    /// count and no volume, and an empty week has neither; a change against either would report
    /// the whole of last week as a gain, or last week's absence as a loss of everything. Two equal
    /// weeks are a change of zero, not `nil`: there was something to compare, and it did not move.
    var lastWeekChange: Weight? {
        guard lastWeek.tonnage > .zero, weekBefore.tonnage > .zero else { return nil }
        return Weight(grams: lastWeek.tonnage.grams - weekBefore.tonnage.grams)
    }

    /// Whether none of the three weeks holds a working set — the one case the card's empty state
    /// survives for (`FR-18.9.2`).
    var isQuiet: Bool {
        thisWeek.workoutCount == 0 && lastWeek.workoutCount == 0 && weekBefore.workoutCount == 0
    }
}

/// `FR-1.9.5`'s weeks, and `FR-1.13.2`'s "has this install ever been used" — one read answering both.
///
/// **One unbounded session read, not two.** Whether anything has *ever* been logged cannot be
/// answered from a bounded range, and the weeks are a filter over what that read already returned,
/// so asking the store twice would put a second unbounded walk on the screen the app launches into
/// for an answer it already has. `NFR-1.6`'s formal number is `T-1.83`'s; this is one caller, not
/// two.
///
/// **The two answers cannot disagree**, which is the other half of folding them together: a screen
/// that decided "first launch" from one read and drew a week summary from another could show a
/// guided empty state above a card reporting three workouts.
@Observable
final class WeekSummaryState {
    /// The three weeks' numbers, or `nil` until the first read answers.
    private(set) var weeks: WeekSummaries?

    /// Whether any session has ever been logged — `FR-1.13.2`'s whole question.
    ///
    /// **Sessions, not working sets.** A lifter who opened a workout and logged nothing is not on
    /// first launch: they have been to Train, and the guided state has nothing left to guide them
    /// towards.
    private(set) var hasEverTrained = false

    /// Whether the first read has answered.
    private(set) var hasLoaded = false

    /// Why the read failed, or `nil`. A retry may work.
    private(set) var failure: String?

    /// The sessions, their entries and their sets.
    private let workouts: any WorkoutRepository

    /// Which days each week holds — the user's own, so `firstWeekday` is theirs (`G-3.4`). The
    /// calendar week, the one History's weeks read (`FR-17.11.3`), not a program's.
    private let calendar: Calendar

    /// What "now" is. Injected so a test can pin a week rather than chase the one it runs in.
    private let now: () -> Date

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - workouts: The sessions and what is under them.
    ///   - calendar: Which days each week holds. Defaults to the user's.
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

    /// Reads every session, then weighs the ones inside the last three weeks — each once, into the
    /// one week it falls in.
    ///
    /// **The set reads are bounded to three weeks of sessions**, which is what keeps the walk small:
    /// a year of training is one session read plus the entries and sets of a few dozen days. Three
    /// weeks rather than one triples what the launch tab reads for this card; that is accepted, not
    /// measured — `NFR-1.1` is met and `DOD-1.2` owes a figure only when a problem appears.
    ///
    /// A session whose entries or sets cannot be read fails the whole summary rather than being
    /// silently omitted — a volume missing one exercise is a wrong number, not a partial one.
    func load() async {
        do {
            let sessions = try await workouts.sessions(
                in: Date.distantPast...Date.distantFuture, includingDeleted: false)
            hasEverTrained = !sessions.isEmpty
            weeks = try await weigh(sessions)
            failure = nil
        } catch {
            failure = String(describing: error)
        }
        hasLoaded = true
    }

    /// Where the three weeks begin and end.
    ///
    /// **Half-open, `[start, end)`.** `DateInterval.contains(_:)` is closed at both ends, so a
    /// session logged at the first instant of a week would fall inside the week before it as well;
    /// the boundaries here are compared directly so that each instant is in exactly one week.
    private struct WeekBounds {
        /// The first instant of the week in progress.
        let thisWeek: Date

        /// The first instant of last week.
        let lastWeek: Date

        /// The first instant of the week before last.
        let weekBefore: Date

        /// The first instant of next week — where the week in progress ends.
        let end: Date
    }

    /// The three weeks around `now()`, or `nil` where the calendar cannot say.
    private var bounds: WeekBounds? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now()),
            let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start),
            let weekBefore = calendar.date(byAdding: .weekOfYear, value: -1, to: lastWeek)
        else { return nil }
        return WeekBounds(
            thisWeek: thisWeek.start, lastWeek: lastWeek, weekBefore: weekBefore, end: thisWeek.end)
    }

    /// Which of the three weeks `date` falls in, or `nil` for a day outside all of them.
    ///
    /// **The training day, not when the row was written** — `FR-1.2.1` backdates, so a session
    /// entered today for last Tuesday belongs to last week and a week summary that read `createdAt`
    /// would credit it to this one.
    private func week(of date: Date, in bounds: WeekBounds) -> WritableKeyPath<Buckets, WeekSummary>? {
        guard date >= bounds.weekBefore, date < bounds.end else { return nil }
        if date >= bounds.thisWeek { return \.thisWeek }
        return date >= bounds.lastWeek ? \.lastWeek : \.weekBefore
    }

    /// The three running totals, keyed so that a session is added to exactly one of them.
    private struct Buckets {
        var thisWeek = WeekSummary.empty
        var lastWeek = WeekSummary.empty
        var weekBefore = WeekSummary.empty
    }

    /// The count and the load of each of the three weeks, from one pass over `sessions`.
    ///
    /// - Parameter sessions: Every session; the ones outside the three weeks are not read into.
    /// - Returns: What each week holds.
    private func weigh(_ sessions: [WorkoutSession]) async throws -> WeekSummaries {
        guard let bounds else {
            return WeekSummaries(thisWeek: .empty, lastWeek: .empty, weekBefore: .empty)
        }
        var buckets = Buckets()
        for session in sessions {
            guard let week = week(of: session.date, in: bounds) else { continue }
            var didTrain = false
            var tonnage = buckets[keyPath: week].tonnage
            let entries = try await workouts.entries(
                forSessionID: session.id, includingDeleted: false)
            for entry in entries {
                let sets = try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
                if sets.contains(where: Tonnage.counts) { didTrain = true }
                tonnage = Tonnage.adding(sets, to: tonnage)
            }
            buckets[keyPath: week] = WeekSummary(
                workoutCount: buckets[keyPath: week].workoutCount + (didTrain ? 1 : 0),
                tonnage: tonnage)
        }
        return WeekSummaries(
            thisWeek: buckets.thisWeek, lastWeek: buckets.lastWeek, weekBefore: buckets.weekBefore)
    }
}
