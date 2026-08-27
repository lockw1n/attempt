import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// `PersonalRecordCacheRepository`'s own contract (`TR-1.6`), which is one reconciliation rather
/// than a save and a delete.
///
/// **The whole reason this repository is in the shared suite.** Its write is the only one in the
/// module that decides per row whether to insert, rewrite, leave alone or soft-delete, and that
/// decision is written twice — once over a `ModelContext`, once over a dictionary. Everything below
/// is a case where the two could have drifted apart and neither side's own tests would say so.
@Suite("Conformance — the personal-record cache")
struct PersonalRecordCacheConformanceTests {
    /// One record, for an N.
    private func values(
        reps: Int,
        grams: Int,
        sourceSetID: UUID = UUID(),
        achievedAt: Date = fixtureCreatedAt,
        version: Int = 1
    ) -> PersonalRecordCacheValues {
        PersonalRecordCacheValues(
            repCount: reps,
            weight: Weight(grams: grams),
            sourceSetID: sourceSetID,
            achievedAt: achievedAt,
            computationVersion: version)
    }

    @Test("What is written is what comes back, ascending by rep count", arguments: Subject.all)
    func aWriteRoundTrips(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        let source = UUID()
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID,
            with: [
                values(reps: 5, grams: 100_000, sourceSetID: source),
                values(reps: 1, grams: 140_000, sourceSetID: source),
            ])

        let stored = try await repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)

        #expect(stored.map(\.repCount) == [1, 5])
        #expect(stored.map(\.weight) == [Weight(grams: 140_000), Weight(grams: 100_000)])
        // One set legitimately holds several rep maxes — the pair, not the source set, is the key.
        #expect(stored.allSatisfy { $0.sourceSetID == source })
        #expect(stored.allSatisfy { $0.exerciseID == exerciseID })
        #expect(stored.allSatisfy { $0.deletedAt == nil })
    }

    /// `FR-1.6.5`'s feed reads this, and the two implementations resolve the order differently — one
    /// over a `ModelContext`, one over a dictionary — so it is the ordering rather than the contents
    /// that this is here for.
    @Test("The cross-exercise read is every live row, newest first", arguments: Subject.all)
    func theFeedReadIsOrderedAndGlobal(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let (squat, bench) = (UUID(), UUID())
        let (older, newer) = (fixtureCreatedAt, fixtureCreatedAt.addingTimeInterval(86_400))
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: squat, with: [values(reps: 3, grams: 140_000, achievedAt: older)])
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: bench, with: [values(reps: 5, grams: 100_000, achievedAt: newer)])

        let feed = try await repositories.personalRecords.personalRecords(includingDeleted: false)

        #expect(feed.map(\.exerciseID) == [bench, squat])
        #expect(feed.map(\.achievedAt) == [newer, older])
    }

    /// **The tie is the common case, not the edge**, which is why the feed's order is only as
    /// deterministic as this: every record one session set carries that session's date, so a lifter
    /// who trains three exercises in a workout has every one of that day's rows tied on `achievedAt`.
    /// The contract names ``StoredRecord/id`` as the second key, and it is the whole reason the
    /// Persistence side sorts in Swift rather than by the descriptor — `id.uuidString` is not a
    /// stored column, so a store-side sort could order the dates and nothing else.
    ///
    /// Asserted as "descending by id within the tie" rather than against a literal order, because
    /// the ids are minted by the write and neither side lets a test choose them. Thirteen rows share
    /// the date, so a wrong tie-break agreeing with this by chance is a 1-in-13! coincidence.
    @Test("Records sharing a date are ordered by id, so the two implementations agree", arguments: Subject.all)
    func theFeedReadBreaksTiesOnID(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let (squat, bench) = (UUID(), UUID())
        let day = fixtureCreatedAt
        // One session's worth of work on each: ten N's from one set, three from another, one date.
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: squat,
            with: (1...10).map { values(reps: $0, grams: 140_000, achievedAt: day) })
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: bench,
            with: (1...3).map { values(reps: $0, grams: 100_000, achievedAt: day) })

        let feed = try await repositories.personalRecords.personalRecords(includingDeleted: false)

        #expect(feed.count == 13)
        #expect(feed.allSatisfy { $0.achievedAt == day }, "the fixture is meant to be all ties")
        #expect(feed.map(\.id) == feed.map(\.id).sorted { $0.uuidString > $1.uuidString })
    }

    /// A record that no longer stands is soft-deleted rather than removed (`G-1.3`), so a read that
    /// ignored the flag would put a superseded record at the top of the feed.
    @Test("A superseded record leaves the feed unless deleted rows are asked for", arguments: Subject.all)
    func theFeedReadRespectsSoftDeletion(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID,
            with: [values(reps: 3, grams: 140_000), values(reps: 5, grams: 100_000)])
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID, with: [values(reps: 3, grams: 140_000)])

        let live = try await repositories.personalRecords.personalRecords(includingDeleted: false)
        let all = try await repositories.personalRecords.personalRecords(includingDeleted: true)

        #expect(live.map(\.repCount) == [3])
        #expect(Set(all.map(\.repCount)) == [3, 5])
    }

    @Test("A record another exercise holds is not touched", arguments: Subject.all)
    func theWriteIsScopedToOneExercise(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let (mine, theirs) = (UUID(), UUID())
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: theirs, with: [values(reps: 3, grams: 90_000)])

        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: mine, with: [values(reps: 3, grams: 200_000)])

        let untouched = try await repositories.personalRecords.personalRecords(
            forExerciseID: theirs, includingDeleted: false)
        #expect(untouched.map(\.weight) == [Weight(grams: 90_000)])
    }

    @Test("A rep count that still holds a record keeps its row and its id", arguments: Subject.all)
    func aRewriteKeepsTheRow(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID, with: [values(reps: 5, grams: 100_000)])
        let before = try #require(
            try await repositories.personalRecords.personalRecords(
                forExerciseID: exerciseID, includingDeleted: false
            ).first)

        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID, with: [values(reps: 5, grams: 105_000)])

        let after = try #require(
            try await repositories.personalRecords.personalRecords(
                forExerciseID: exerciseID, includingDeleted: false
            ).first)
        // `FR-1.6.2` links to a record; a rewrite that minted a new row would break every link to
        // an N whose weight moved, which is exactly the N a screen was showing.
        #expect(after.id == before.id)
        #expect(after.createdAt == before.createdAt)
        #expect(after.weight == Weight(grams: 105_000))
        #expect(after.updatedAt > before.updatedAt)
    }

    @Test("A rep count left out of the write is soft-deleted, not erased", arguments: Subject.all)
    func aRecordThatNoLongerStandsIsSoftDeleted(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID,
            with: [values(reps: 1, grams: 140_000), values(reps: 5, grams: 100_000)])

        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID, with: [values(reps: 1, grams: 140_000)])

        let live = try await repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(live.map(\.repCount) == [1])

        let all = try await repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: true)
        #expect(all.map(\.repCount) == [1, 5])
        let swept = try #require(all.first { $0.repCount == 5 })
        #expect(swept.deletedAt != nil)
    }

    @Test("An empty write sweeps every row the exercise had", arguments: Subject.all)
    func anEmptyWriteClearsTheExercise(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID, with: [values(reps: 2, grams: 120_000)])

        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID, with: [])

        #expect(
            try await repositories.personalRecords.personalRecords(
                forExerciseID: exerciseID, includingDeleted: false
            ).isEmpty)
        #expect(
            try await repositories.personalRecords.personalRecords(
                forExerciseID: exerciseID, includingDeleted: true
            ).count == 1)
    }

    /// **`G-2.4`, and the case a recompute is in almost every time it runs.** A logged set that beat
    /// nothing recomputes the same ten records, and a write that restamped them would put a local
    /// no-op ahead of a real remote edit on the conflict key — ten rows per set logged.
    @Test("A write that says what is already stored writes nothing", arguments: Subject.all)
    func anUnchangedRecordIsNotRestamped(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        let unchanged = values(reps: 5, grams: 100_000)
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID, with: [unchanged])
        let before = try #require(
            try await repositories.personalRecords.personalRecords(
                forExerciseID: exerciseID, includingDeleted: false
            ).first)

        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID, with: [unchanged])

        let after = try #require(
            try await repositories.personalRecords.personalRecords(
                forExerciseID: exerciseID, includingDeleted: false
            ).first)
        #expect(after.updatedAt == before.updatedAt)
    }

    /// The rules version travels with the row and is never interpreted here — a caller compares it
    /// against its own, which is the only place that knows what it computed under.
    @Test("computationVersion is stored as given, including a stale one", arguments: Subject.all)
    func theVersionIsCarried(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.personalRecords.replacePersonalRecords(
            forExerciseID: exerciseID, with: [values(reps: 3, grams: 80_000, version: 0)])

        let stored = try await repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(stored.map(\.computationVersion) == [0])
    }

    @Test("An exercise with no cache reads as empty rather than failing", arguments: Subject.all)
    func anUnknownExerciseIsEmpty(_ subject: Subject) async throws {
        let repositories = try subject.make()
        #expect(
            try await repositories.personalRecords.personalRecords(
                forExerciseID: UUID(), includingDeleted: true
            ).isEmpty)
    }
}
