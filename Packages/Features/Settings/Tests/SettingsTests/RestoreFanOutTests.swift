import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues
@testable import Settings

/// What a restore costs the record cache (`FR-1.11.4`, `NFR-1.6`, `G-1.5`).
///
/// **The shape, not the clock.** `StoreRestore` used to announce once per restored *session*, and
/// each announcement walked every exercise that session touched over its whole history — so an
/// exercise trained fifty times was walked fifty times, each walk longer than the last as the rows
/// landed. Measured over real logs that came out worse than superlinear: five times the sets cost
/// twenty-one times the time, 10.6 s at 3,065 sets against 224.7 s at 15,325. A wall-clock
/// assertion over a fixture small enough to commit would pass either way; counting the walks is
/// what says the fan-out is gone.
///
/// **The count is taken at the cache write rather than at the history read**, because that is the
/// one call every walk makes and the one the restore's own repositories can be swapped underneath.
/// A walk that decides to write nothing still calls it, and one that never happened cannot.
@Suite("Restore fan-out")
struct RestoreFanOutTests {
    /// How many sessions the fixture's most-trained exercise holds — well above the two exercises,
    /// so a per-session fan-out and a per-exercise one cannot produce the same number.
    private static let sessionsOfTheSquat = 6

    /// A backup of a log training one exercise repeatedly and another twice.
    private static func manySessions() async throws -> TrainingLogArchive {
        let log = ExportLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        for day in 0..<sessionsOfTheSquat {
            let session = try await log.session(daysAgo: day)
            let entry = try await log.entry(squat, in: session)
            _ = try await log.set(in: entry, order: 0, grams: 100_000 + day * 1_000, reps: 5)
            if day < 2 {
                let other = try await log.entry(bench, in: session, order: 1)
                _ = try await log.set(in: other, order: 0, grams: 80_000, reps: 5)
            }
        }
        return try await log.backup.archive(takenAt: ExportLog.epoch)
    }

    @Test("A restore recomputes each exercise once, however many sessions trained it")
    func eachExerciseIsRecomputedOnce() async throws {
        let archive = try await Self.manySessions()
        let target = InMemoryRepositoryStack()
        let counting = CountingRecordCache(wrapped: target.personalRecords)

        try await Self.restore(into: target, cache: counting).restore(archive)

        // Two exercises, two recomputes — not eight, which is what one per session over the six
        // squat days and the two bench ones would have cost.
        #expect(await counting.writes.count == 2)
        #expect(Set(await counting.writes) == Set(archive.exercises.map(\.id)))
    }

    /// **The restore still leaves a usable cache**, which the count above cannot say on its own: a
    /// fan-out removed by announcing nothing would satisfy it perfectly.
    @Test("And the records it wrote are the ones the log earned")
    func theCacheIsRebuilt() async throws {
        let archive = try await Self.manySessions()
        let target = InMemoryRepositoryStack()

        try await Self.restore(into: target, cache: target.personalRecords).restore(archive)

        let cached = try await target.personalRecords.personalRecords(includingDeleted: false)
        #expect(!cached.isEmpty)
        // The heaviest squat of the six sessions is what stands, so the walk read the whole
        // history rather than one session's.
        let squatBest =
            cached
            .filter { !$0.isConfirmedZero && $0.weight.grams > 90_000 }
            .map(\.weight.grams).max()
        #expect(squatBest == 100_000 + (Self.sessionsOfTheSquat - 1) * 1_000)
    }

    /// The restore under test, with the cache repository the recomputer writes through swapped.
    ///
    /// - Parameters:
    ///   - stack: The store to restore into.
    ///   - cache: What the recompute writes its rows to.
    /// - Returns: The restore.
    private static func restore(
        into stack: InMemoryRepositoryStack, cache: any PersonalRecordCacheRepository
    ) -> StoreRestore {
        StoreRestore(
            exercises: stack.exercises,
            trainingMaxes: stack.trainingMaxes,
            workouts: stack.workouts,
            bodyweight: stack.bodyweight,
            equipment: stack.equipment,
            routines: stack.routines,
            programs: stack.programs,
            settings: stack.settings,
            records: PersonalRecordRecomputer(workouts: stack.workouts, cache: cache))
    }
}

/// Everything the cache fake does, and a record of which exercises were written.
///
/// One entry per `replacePersonalRecords(forExerciseID:with:)` call, in order — so the assertion can
/// be about how many times an exercise was walked as well as about which were.
actor CountingRecordCache: PersonalRecordCacheRepository {
    private let wrapped: any PersonalRecordCacheRepository

    /// The exercises whose rows were written, once per call.
    private(set) var writes: [UUID] = []

    init(wrapped: any PersonalRecordCacheRepository) {
        self.wrapped = wrapped
    }

    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [PersonalRecordCache] {
        try await wrapped.personalRecords(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func personalRecords(includingDeleted: Bool) async throws -> [PersonalRecordCache] {
        try await wrapped.personalRecords(includingDeleted: includingDeleted)
    }

    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) async throws {
        writes.append(exerciseID)
        try await wrapped.replacePersonalRecords(forExerciseID: exerciseID, with: values)
    }
}
