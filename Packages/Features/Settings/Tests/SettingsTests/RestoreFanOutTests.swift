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

    /// A backup of a log training one exercise repeatedly, another twice, and a third never.
    ///
    /// **The untrained exercise is what separates the two fan-outs that both answer "once each".**
    /// A fixture whose catalogue is exactly its trained set cannot tell one walk per *trained*
    /// exercise from one walk per *catalogue* exercise — and the second is the whole-catalogue sweep
    /// `NFR-17.2` took off the launch path, measured at 0.56 s and 1.41 s over the author's log.
    private static func manySessions() async throws -> Fixture {
        let log = ExportLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        let untrained = try await log.exercise(named: "Overhead Press")
        for day in 0..<sessionsOfTheSquat {
            let session = try await log.session(daysAgo: day)
            let entry = try await log.entry(squat, in: session)
            _ = try await log.set(in: entry, order: 0, grams: 100_000 + day * 1_000, reps: 5)
            if day < 2 {
                let other = try await log.entry(bench, in: session, order: 1)
                _ = try await log.set(in: other, order: 0, grams: 80_000, reps: 5)
            }
        }
        return Fixture(
            archive: try await log.backup.archive(takenAt: ExportLog.epoch),
            trained: [squat.id, bench.id],
            untrained: untrained.id)
    }

    /// The backup, the exercises its sessions train, and the one in its catalogue that they do not.
    private struct Fixture {
        let archive: TrainingLogArchive
        let trained: Set<UUID>
        let untrained: UUID
    }

    @Test("A restore recomputes each trained exercise once, however many sessions trained it")
    func eachExerciseIsRecomputedOnce() async throws {
        let fixture = try await Self.manySessions()
        let target = InMemoryRepositoryStack()
        let counting = CountingRecordCache(wrapped: target.personalRecords)

        try await Self.restore(into: target, cache: counting).restore(fixture.archive)

        // Two exercises, two recomputes — not eight, which is what one per session over the six
        // squat days and the two bench ones would have cost.
        #expect(await counting.writes.count == 2)
        #expect(Set(await counting.writes) == fixture.trained)
        // And not three: the exercise the file carries but never trained is not walked, which is
        // what says the announcement is read off `entries` rather than off the catalogue.
        #expect(!(await counting.writes).contains(fixture.untrained))
        #expect(fixture.archive.exercises.contains { $0.id == fixture.untrained })
    }

    /// **The restore still leaves a usable cache**, which the count above cannot say on its own: a
    /// fan-out removed by announcing nothing would satisfy it perfectly.
    @Test("And the records it wrote are the ones the log earned")
    func theCacheIsRebuilt() async throws {
        let archive = try await Self.manySessions().archive
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
