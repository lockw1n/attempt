import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

@Suite("Training entities")
struct TrainingEntitiesTests {
    @Test("ExerciseEntity honours the conventions against a real store")
    func exerciseHonoursConventions() throws {
        let context = try makeTrainingContext()
        try assertStoredEntityConventions({ makeSquat() }, in: context)
    }

    @Test("WorkoutSessionEntity honours the conventions against a real store")
    func sessionHonoursConventions() throws {
        let context = try makeTrainingContext()
        try assertStoredEntityConventions({ WorkoutSessionEntity(date: .distantPast) }, in: context)
    }

    @Test("ExerciseEntryEntity honours the conventions against a real store")
    func entryHonoursConventions() throws {
        let context = try makeTrainingContext()
        try assertStoredEntityConventions(
            { ExerciseEntryEntity(sessionID: UUID(), exerciseID: UUID(), order: 0) },
            in: context
        )
    }

    // The one call site that names SetEntryEntity's initialiser directly rather than going through
    // the fixture, so the signature G-1.8 rests on is exercised as written.
    @Test("SetEntryEntity honours the conventions against a real store")
    func setHonoursConventions() throws {
        let context = try makeTrainingContext()
        try assertStoredEntityConventions(
            {
                SetEntryEntity(
                    entryID: UUID(),
                    order: 0,
                    weightGrams: 100_000,
                    reps: 5,
                    isWarmup: false,
                    isCompleted: true
                )
            },
            in: context
        )
    }

    // The shape a repository actually reads back: two exercises in one session, five sets between
    // them, reassembled by UUID because the schema declares no relationships (G-2.5). Everything is
    // inserted in scrambled order, so a fetch that leaned on insertion order would answer wrongly.
    @Test("A session with two exercises and five sets persists and re-reads")
    func sessionRoundTrips() throws {
        let context = try makeTrainingContext()
        let squat = makeSquat()
        let bench = makeBench()
        let session = WorkoutSessionEntity(date: Date(timeIntervalSince1970: 1_700_000_000))
        let squatEntry = ExerciseEntryEntity(sessionID: session.id, exerciseID: squat.id, order: 0)
        let benchEntry = ExerciseEntryEntity(sessionID: session.id, exerciseID: bench.id, order: 1)
        let sets = [
            (benchEntry.id, 1, 105_000),
            (squatEntry.id, 2, 150_000),
            (squatEntry.id, 0, 140_000),
            (benchEntry.id, 0, 100_000),
            (squatEntry.id, 1, 145_000),
        ].map { entryID, order, grams in
            makeSet(
                entryID: entryID,
                order: order,
                isWarmup: false,
                isCompleted: true,
                weightGrams: grams
            )
        }

        for model in [squat, bench] { context.insert(model) }
        context.insert(session)
        for model in [benchEntry, squatEntry] { context.insert(model) }
        for model in sets { context.insert(model) }
        let stamp = Date(timeIntervalSince1970: 1_700_003_600)
        try context.saveStamped(at: stamp)

        let storedSession = try #require(
            try context.fetch(FetchDescriptor<WorkoutSessionEntity>.notDeleted()).first
        )
        let sessionID = storedSession.id
        let entries = try context.fetch(
            FetchDescriptor<ExerciseEntryEntity>.notDeleted(
                matching: #Predicate { $0.sessionID == sessionID },
                sortBy: [SortDescriptor(\.order)]
            )
        )

        #expect(storedSession.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(entries.map(\.order) == [0, 1])
        #expect(entries.map(\.exerciseID) == [squat.id, bench.id])

        var loadsByExercise: [UUID: [Int]] = [:]
        for entry in entries {
            loadsByExercise[entry.exerciseID] = try loadsInOrder(ofEntry: entry.id, in: context)
        }

        #expect(loadsByExercise[squat.id] == [140_000, 145_000, 150_000])
        #expect(loadsByExercise[bench.id] == [100_000, 105_000])
        // G-2.4: every row this transaction inserted carries the stamp, including four types that
        // did not exist when saveStamped(at:) was written.
        #expect(storedSession.updatedAt == stamp)
        #expect(entries.map(\.updatedAt) == [stamp, stamp])
    }

    // TR-0.2.8's "ties resolve to the earlier set" is positional, so the sort key that makes it mean
    // chronological — (session.date, entry.order, set.order) — has to be expressible from the schema
    // alone. Four entries across two sessions, inserted in an order matching none of it.
    @Test("The three ordering fields compose into one chronological key")
    func orderingFieldsComposeChronologically() throws {
        let context = try makeTrainingContext()
        let monday = WorkoutSessionEntity(date: Date(timeIntervalSince1970: 1_000_000))
        let tuesday = WorkoutSessionEntity(date: Date(timeIntervalSince1970: 1_086_400))
        let exercise = makeSquat()
        let entries = [
            ExerciseEntryEntity(sessionID: tuesday.id, exerciseID: exercise.id, order: 1),
            ExerciseEntryEntity(sessionID: monday.id, exerciseID: exercise.id, order: 1),
            ExerciseEntryEntity(sessionID: monday.id, exerciseID: exercise.id, order: 0),
            ExerciseEntryEntity(sessionID: tuesday.id, exerciseID: exercise.id, order: 0),
        ]
        for model in [monday, tuesday] { context.insert(model) }
        for model in entries { context.insert(model) }
        for (index, entry) in entries.enumerated() {
            context.insert(
                makeSet(
                    entryID: entry.id,
                    order: 0,
                    isWarmup: false,
                    isCompleted: true,
                    weightGrams: 100_000 + index * 1_000
                )
            )
        }
        try context.saveStamped()

        let sessionDates = try Dictionary(
            uniqueKeysWithValues: context.fetch(FetchDescriptor<WorkoutSessionEntity>.notDeleted())
                .map { ($0.id, $0.date) }
        )
        // #require rather than a guard in the comparator: a sessionID that resolved to nothing would
        // otherwise leave the sort a no-op and be read as a passing chronological order.
        let keys = try context.fetch(FetchDescriptor<ExerciseEntryEntity>.notDeleted())
            .map { entry in (id: entry.id, date: try #require(sessionDates[entry.sessionID]), order: entry.order) }
        let sorted = keys.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.order < rhs.order : lhs.date < rhs.date
        }
        var loads: [Int] = []
        for key in sorted {
            loads.append(contentsOf: try loadsInOrder(ofEntry: key.id, in: context))
        }

        // Monday's two entries first, in entry order, then Tuesday's — the reverse of the insertion
        // order for three of the four.
        #expect(sorted.map(\.order) == [0, 1, 0, 1])
        #expect(loads == [102_000, 101_000, 103_000, 100_000])
    }

    // G-1.3: a soft-deleted set stays in the store and out of every default read, so removing one
    // set leaves its siblings and its entry untouched.
    @Test("Soft-deleting one set leaves its siblings and its entry alone")
    func softDeletingOneSet() throws {
        let context = try makeTrainingContext()
        let entry = ExerciseEntryEntity(sessionID: UUID(), exerciseID: UUID(), order: 0)
        let sets = (0..<3).map { order in
            makeSet(entryID: entry.id, order: order, isWarmup: false, isCompleted: true)
        }
        context.insert(entry)
        for model in sets { context.insert(model) }
        try context.saveStamped()

        sets[1].markDeleted()
        try context.saveStamped()

        let live = try context.fetch(
            FetchDescriptor<SetEntryEntity>.notDeleted(sortBy: [SortDescriptor(\.order)])
        )
        let all = try context.fetch(FetchDescriptor<SetEntryEntity>.includingDeleted())

        #expect(live.map(\.order) == [0, 2])
        #expect(all.count == 3)
        #expect(try context.fetch(FetchDescriptor<ExerciseEntryEntity>.notDeleted()).count == 1)
    }
}
