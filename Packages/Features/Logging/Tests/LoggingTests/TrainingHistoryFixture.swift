import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

// A file of its own on `SessionSnapshotFixtures`' argument: the suite beside this one and the
// history it reads grow for different reasons — a case being added, and a column being added to
// every row — and together they outgrow `file_length`.

/// Three finished workouts and the sets logged in them — a history with no workout in progress.
struct TrainingHistory {
    /// The store the sets live in.
    let repositories: InMemoryRepositoryStack

    /// What performs the edit and the deletion.
    let writer: LoggedSetWriter

    /// One exercise entry per workout, newest first — the order the repository answers sessions in.
    let entries: [ExerciseEntry]

    /// That entry's sets, in the same order.
    let sets: [[SetEntry]]

    /// Three workouts a week apart, each finished, each with two sets logged against one exercise.
    ///
    /// - Returns: The history.
    static func threeSessions() async throws -> TrainingHistory {
        let repositories = InMemoryRepositoryStack()
        let catalogue = try await Workout.seed(into: repositories)
        var entries: [ExerciseEntry] = []
        var sets: [[SetEntry]] = []
        for week in 0..<3 {
            let entry = try await workout(
                weeksAgo: week, exerciseID: catalogue[week].id, in: repositories)
            entries.append(entry)
            sets.append(
                try await repositories.workouts.sets(forEntryID: entry.id, includingDeleted: false))
        }
        return TrainingHistory(
            repositories: repositories,
            writer: LoggedSetWriter(
                repository: repositories.workouts,
                records: PersonalRecordRecomputer(
                    workouts: repositories.workouts,
                    cache: repositories.personalRecords)),
            entries: entries,
            sets: sets
        )
    }

    /// One finished workout, with one exercise in it and two sets logged against that.
    ///
    /// - Parameters:
    ///   - week: How many weeks ago it was trained.
    ///   - exerciseID: The catalogue row the entry names.
    ///   - repositories: Where it is written.
    /// - Returns: The exercise entry, which is what the sets are read by.
    private static func workout(
        weeksAgo week: Int, exerciseID: UUID, in repositories: InMemoryRepositoryStack
    ) async throws -> ExerciseEntry {
        let day = Date(timeIntervalSince1970: 1_700_000_000 - Double(week) * 604_800)
        let session = WorkoutSession(
            id: UUID(),
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            date: day,
            startedAt: day,
            // Finished, which is what makes each of these a *past* session: nothing in the app
            // would resume one, and no store holds it.
            endedAt: day.addingTimeInterval(3600),
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        try await repositories.workouts.save(session)
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exerciseID,
            order: 0,
            notes: ""
        )
        try await repositories.workouts.save(entry)
        for position in 0..<2 {
            try await repositories.workouts.save(
                SetEntry(
                    id: UUID(),
                    createdAt: day,
                    updatedAt: day,
                    deletedAt: nil,
                    entryID: entry.id,
                    order: position,
                    weight: Weight(grams: 100_000 + week * 2_500),
                    reps: 5,
                    rpe: 8,
                    rir: nil,
                    isWarmup: false,
                    isCompleted: true,
                    targetWeight: nil,
                    targetReps: nil,
                    // Two of them, one built-in and one outside the vocabulary, so an edit that
                    // dropped or rewrote the column fails rather than comparing empty to empty.
                    modifiers: [SetModifier(.belt), SetModifier(rawValue: "chains")],
                    notes: "",
                    completedAt: day
                ))
        }
        return entry
    }

    /// The sets logged in one of the three workouts, as they were written.
    ///
    /// - Parameter index: `0` is the most recent, matching ``entries``; `2` is three sessions ago.
    /// - Returns: Its sets.
    func sets(inSession index: Int) -> [SetEntry] {
        sets[index]
    }

    /// One set as it is stored now, or `nil` if it is no longer live.
    ///
    /// - Parameters:
    ///   - id: The set.
    ///   - entryID: The entry it belongs to.
    /// - Returns: The stored row.
    func stored(id: UUID, inEntryID entryID: UUID) async throws -> SetEntry? {
        try await repositories.workouts
            .sets(forEntryID: entryID, includingDeleted: false)
            .first { $0.id == id }
    }

    /// Every live set in the other two workouts, whole rather than by field.
    ///
    /// - Parameter index: The workout to leave out.
    /// - Returns: Their sets.
    func everySet(exceptInSession index: Int) async throws -> [SetEntry] {
        var others: [SetEntry] = []
        for (position, entry) in entries.enumerated() where position != index {
            others += try await repositories.workouts.sets(
                forEntryID: entry.id, includingDeleted: false)
        }
        return others
    }
}
