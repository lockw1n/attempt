import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

// TR-1.14, G-1.3. Every test here runs against a real store through `RepositoryHarness`, because
// the thing under test is what the store holds afterwards and a fake cannot be wrong about that.
//
// Rows are seeded rather than written through the repositories: a soft-deleted exercise, a live row
// under a deleted parent and a duplicate id are all states this layer refuses to produce and can
// still receive, and they are exactly the cases the retention rule exists for.

@Suite("Store purge")
struct StorePurgeTests {
    private let longAgo = Date(timeIntervalSince1970: 1_000_000)
    private let cutoff = Date(timeIntervalSince1970: 1_500_000)
    private let lately = Date(timeIntervalSince1970: 2_000_000)

    private func softDeleted<T: StoredEntity>(_ row: T, at when: Date) -> T {
        row.deletedAt = when
        return row
    }

    // A branch nothing outside it names: the whole thing is free, and the count is spelled out so a
    // routine that removed the session and orphaned its sets could not pass.
    @Test("A soft-deleted session takes its entries and their sets")
    func deletedBranchGoesWhole() async throws {
        let harness = try RepositoryHarness()
        let squat = makeSquat()
        let session = softDeleted(WorkoutSessionEntity(date: longAgo), at: longAgo)
        let entry = softDeleted(
            ExerciseEntryEntity(sessionID: session.id, exerciseID: squat.id, order: 0), at: longAgo)
        let sets = (0..<3).map {
            softDeleted(
                makeSet(entryID: entry.id, order: $0, isWarmup: false, isCompleted: true),
                at: longAgo)
        }
        try harness.seed([squat, session, entry] + sets)

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 5)
        #expect(report.retained == 0)
        #expect(try count(WorkoutSessionEntity.self, in: harness) == 0)
        #expect(try count(ExerciseEntryEntity.self, in: harness) == 0)
        #expect(try count(SetEntryEntity.self, in: harness) == 0)
        #expect(try count(ExerciseEntity.self, in: harness) == 1)
    }

    // The rule's second half. A live entry is not eligible, and being a referrer it keeps the
    // session too — so a pass that removed anything at all here would have hard-deleted live data.
    @Test("A live entry under a deleted session holds both in the store")
    func liveChildHoldsDeletedParent() async throws {
        let harness = try RepositoryHarness()
        let squat = makeSquat()
        let session = softDeleted(WorkoutSessionEntity(date: longAgo), at: longAgo)
        let entry = ExerciseEntryEntity(sessionID: session.id, exerciseID: squat.id, order: 0)
        try harness.seed([squat, session, entry])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 0)
        #expect(report.retained == 1)
        #expect(try count(WorkoutSessionEntity.self, in: harness) == 1)
    }

    // Transitivity, which is the whole reason the scan iterates: the set keeps the entry, and only
    // then does the entry keep the session. A single ordered pass over the edges frees the session
    // before it learns the entry survived.
    @Test("A live set two levels down holds the entry and the session")
    func retentionIsTransitive() async throws {
        let harness = try RepositoryHarness()
        let squat = makeSquat()
        let session = softDeleted(WorkoutSessionEntity(date: longAgo), at: longAgo)
        let entry = softDeleted(
            ExerciseEntryEntity(sessionID: session.id, exerciseID: squat.id, order: 0), at: longAgo)
        let live = makeSet(entryID: entry.id, order: 0, isWarmup: false, isCompleted: true)
        try harness.seed([squat, session, entry, live])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 0)
        #expect(report.retained == 2)
        #expect(try count(WorkoutSessionEntity.self, in: harness) == 1)
        #expect(try count(ExerciseEntryEntity.self, in: harness) == 1)
    }

    // G-1.4. The cache row is live, so under the plain rule it would be a referrer and would keep
    // the set it was computed from — a derived value deciding the fate of its own source. It goes
    // with the set instead.
    @Test("A live cache row does not hold its source set, and goes with it")
    func cacheNeverHoldsItsSource() async throws {
        let harness = try RepositoryHarness()
        let squat = makeSquat()
        let session = softDeleted(WorkoutSessionEntity(date: longAgo), at: longAgo)
        let entry = softDeleted(
            ExerciseEntryEntity(sessionID: session.id, exerciseID: squat.id, order: 0), at: longAgo)
        let set = softDeleted(
            makeSet(entryID: entry.id, order: 0, isWarmup: false, isCompleted: true), at: longAgo)
        let cached = PersonalRecordCacheEntity(
            exerciseID: squat.id,
            repCount: 5,
            weightGrams: 100_000,
            sourceSetID: set.id,
            achievedAt: longAgo,
            computationVersion: 1
        )
        try harness.seed([squat, session, entry, set, cached])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 4)
        #expect(report.retained == 0)
        #expect(try count(SetEntryEntity.self, in: harness) == 0)
        #expect(try count(PersonalRecordCacheEntity.self, in: harness) == 0)
    }

    // A soft-deleted exercise cannot be produced by this layer, but a foreign row can arrive that
    // way — and the catalogue is named by four different columns, all four driven here. The entry
    // is the one that carries real traffic: every logged set hangs off one, so an unheld edge there
    // is the orphan this whole file exists to make unreachable.
    @Test("A live entry, training max, settings row, variant or routine slot holds a deleted exercise")
    func catalogueReferrersHoldAnExercise() async throws {
        for referrer in ExerciseReferrer.allCases {
            let harness = try RepositoryHarness()
            let squat = softDeleted(makeSquat(), at: longAgo)
            var rows: [any PersistentModel] = [squat]
            switch referrer {
            case .entry:
                let session = WorkoutSessionEntity(date: longAgo)
                rows.append(session)
                rows.append(
                    ExerciseEntryEntity(sessionID: session.id, exerciseID: squat.id, order: 0))
            case .trainingMax:
                rows.append(makeTrainingMaxConfig(exerciseID: squat.id, source: .manual))
            case .dashboard:
                let settings = makeSettings(userID: UUID())
                settings.dashboardExerciseIDs = [squat.id]
                rows.append(settings)
            case .variant:
                rows.append(
                    ExerciseEntity(
                        name: "Pause Squat",
                        movement: .squat,
                        equipment: .barbell,
                        laterality: .bilateral,
                        barType: .standard,
                        isCustom: true,
                        parentExerciseID: squat.id
                    ))
            case .routineSlot:
                let routine = RoutineEntity(name: "Squat day")
                rows.append(routine)
                rows.append(
                    RoutineExerciseEntity(
                        routineID: routine.id, exerciseID: squat.id, order: 0))
            }
            try harness.seed(rows)

            let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

            #expect(report.removed == 0, "\(referrer) did not hold the exercise")
            #expect(report.retained == 1, "\(referrer) did not hold the exercise")
            #expect(try count(ExerciseEntity.self, in: harness) == (referrer == .variant ? 2 : 1))
        }
    }

    // The bound is inclusive, and the row on the other side of it is what proves the comparison is
    // not simply "is it deleted at all".
    @Test("The cutoff is inclusive, and a later deletion stays")
    func cutoffIsInclusive() async throws {
        let harness = try RepositoryHarness()
        let onTheBoundary = softDeleted(
            BodyweightEntryEntity(date: longAgo, weightGrams: 80_000, source: .manual), at: cutoff)
        let afterIt = softDeleted(
            BodyweightEntryEntity(date: longAgo, weightGrams: 81_000, source: .manual), at: lately)
        let live = BodyweightEntryEntity(date: longAgo, weightGrams: 82_000, source: .manual)
        try harness.seed([onTheBoundary, afterIt, live])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 1)
        #expect(report.retained == 0)
        let left = try harness.store().rows(BodyweightEntryEntity.self, includingDeleted: true)
        #expect(Set(left.map(\.weightGrams)) == [81_000, 82_000])
    }

    // G-2.5 leaves uniqueness to the repositories, so two rows may share an id. Removing the
    // eligible half would leave anything naming that id resolving to the live one — correct — but
    // the plan works in id space, so it has to notice the live half rather than count rows.
    @Test("An id carried by both a deleted and a live row is not freed")
    func duplicateIDWithALiveHalfStays() async throws {
        let harness = try RepositoryHarness()
        let shared = UUID()
        let deleted = softDeleted(
            BodyweightEntryEntity(id: shared, date: longAgo, weightGrams: 80_000, source: .manual),
            at: longAgo)
        let live = BodyweightEntryEntity(
            id: shared, date: longAgo, weightGrams: 81_000, source: .manual)
        try harness.seed([deleted, live])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 0)
        #expect(report.retained == 1)
        #expect(try count(BodyweightEntryEntity.self, in: harness) == 2)
    }

    // DOD-1.3's wipe. Nothing survives, so nothing can be a referrer and the retention rule is
    // vacuous — which is what makes the wipe the same routine rather than a second one.
    @Test("Purging everything empties the store, live rows included")
    func everythingEmptiesTheStore() async throws {
        let harness = try RepositoryHarness()
        let squat = makeSquat()
        let session = WorkoutSessionEntity(date: longAgo)
        let entry = ExerciseEntryEntity(sessionID: session.id, exerciseID: squat.id, order: 0)
        let set = makeSet(entryID: entry.id, order: 0, isWarmup: false, isCompleted: true)
        let routine = RoutineEntity(name: "Squat day")
        let slot = RoutineExerciseEntity(routineID: routine.id, exerciseID: squat.id, order: 0)
        try harness.seed([
            squat,
            session,
            entry,
            set,
            makeTrainingMaxConfig(exerciseID: squat.id, source: .manual),
            BodyweightEntryEntity(date: longAgo, weightGrams: 80_000, source: .manual),
            EquipmentProfileEntity(
                name: "Home",
                barWeightGrams: 20_000,
                collarWeightGrams: 0,
                plateGrams: [25_000],
                platePairCounts: [2]
            ),
            makeSettings(userID: UUID()),
            PersonalRecordCacheEntity(
                exerciseID: squat.id,
                repCount: 5,
                weightGrams: 100_000,
                sourceSetID: set.id,
                achievedAt: longAgo,
                computationVersion: 1
            ),
            routine,
            slot,
            RoutineTargetGroupEntity(
                routineExerciseID: slot.id,
                order: 0,
                targetWeightGrams: 90_000,
                targetReps: 4,
                targetSets: 4
            ),
            PlannedTargetGroupEntity(
                exerciseEntryID: entry.id,
                order: 0,
                targetWeightGrams: 90_000,
                targetReps: 4,
                targetSets: 4
            ),
        ])

        let report = try await harness.stack.purge(.everything)

        // Anchored to `SchemaV1.models.count` rather than to a literal, and that is the whole
        // point of the assertion rather than a flourish. This test seeded exactly one row per
        // entity type; a literal count passes vacuously for an entity added later and never
        // seeded, which is how `PurgePlan` came to be blind to three tables at once. Against the
        // schema's own list, the next entity added without a fixture here turns this red.
        #expect(report.removed == SchemaV1.models.count)
        #expect(report.retained == 0)
        let remainingCounts = try remainingCounts(in: harness)
        #expect(remainingCounts.count == SchemaV1.models.count, "a table is missing from the count")
        for remaining in remainingCounts {
            #expect(remaining.value == 0, "\(remaining.key) still holds rows")
        }
    }

    // The purge writes through `saveStamped`, which restamps every inserted or changed row — and
    // `updatedAt` is G-2.4's conflict key, so a survivor restamped by someone else's deletion would
    // outrank a real remote edit.
    @Test("A surviving row's updatedAt is untouched")
    func survivorsAreNotRestamped() async throws {
        let harness = try RepositoryHarness()
        let stamped = Date(timeIntervalSince1970: 900_000)
        let live = BodyweightEntryEntity(
            date: longAgo, weightGrams: 82_000, source: .manual, updatedAt: stamped)
        let goes = softDeleted(
            BodyweightEntryEntity(
                date: longAgo, weightGrams: 80_000, source: .manual, updatedAt: stamped),
            at: longAgo)
        try harness.seed([live, goes])

        _ = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        let left = try harness.store().rows(BodyweightEntryEntity.self, includingDeleted: true)
        #expect(left.count == 1)
        #expect(left.first?.updatedAt == stamped)
    }

    // G-1.4's other half, and the clause the test above cannot reach: this cache row's source set
    // survives, so the only thing that can doom it is the exercise it names. Being a derived row it
    // is not a referrer, so it does not hold that exercise back either — it goes, and the set it was
    // computed from is left exactly where it was.
    @Test("A live cache row goes with the deleted exercise it names, and its set stays")
    func cacheGoesWithItsExercise() async throws {
        let harness = try RepositoryHarness()
        let squat = softDeleted(makeSquat(), at: longAgo)
        let sourceSet = makeSet(entryID: UUID(), order: 0, isWarmup: false, isCompleted: true)
        let cached = PersonalRecordCacheEntity(
            exerciseID: squat.id,
            repCount: 5,
            weightGrams: 100_000,
            sourceSetID: sourceSet.id,
            achievedAt: longAgo,
            computationVersion: 1
        )
        try harness.seed([squat, sourceSet, cached])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 2)
        #expect(report.retained == 0)
        #expect(try count(ExerciseEntity.self, in: harness) == 0)
        #expect(try count(PersonalRecordCacheEntity.self, in: harness) == 0)
        #expect(try count(SetEntryEntity.self, in: harness) == 1)
    }

    // The cache is the one table whose fate is read off what it names rather than off its own id,
    // so the duplicate-id spare has to be proved on it separately — and `retained` is the only
    // place that shows. Neither half is doomed here: the exercise and the set both survive.
    @Test("An eligible cache row spared by a duplicate id is reported as retained")
    func duplicateCacheIDIsRetained() async throws {
        let harness = try RepositoryHarness()
        let squat = makeSquat()
        let sourceSet = makeSet(entryID: UUID(), order: 0, isWarmup: false, isCompleted: true)
        let shared = UUID()
        let deleted = softDeleted(
            PersonalRecordCacheEntity(
                id: shared,
                exerciseID: squat.id,
                repCount: 5,
                weightGrams: 100_000,
                sourceSetID: sourceSet.id,
                achievedAt: longAgo,
                computationVersion: 1
            ), at: longAgo)
        let live = PersonalRecordCacheEntity(
            id: shared,
            exerciseID: squat.id,
            repCount: 5,
            weightGrams: 102_500,
            sourceSetID: sourceSet.id,
            achievedAt: longAgo,
            computationVersion: 1
        )
        try harness.seed([squat, sourceSet, deleted, live])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 0)
        #expect(report.retained == 1)
        #expect(try count(PersonalRecordCacheEntity.self, in: harness) == 2)
    }

    @Test("A purge over an empty store removes and retains nothing")
    func emptyStoreIsNoOp() async throws {
        let harness = try RepositoryHarness()

        let report = try await harness.stack.purge(.everything)

        #expect(report == PurgeReport(removed: 0, retained: 0))
    }
}

// The two helpers the suite's assertions are built from, at file scope rather than inside the
// struct: they are about the store rather than about any one test, and a suite this long has a
// body-length ceiling to stay under.

private func count<T: StoredEntity>(
    _ type: T.Type,
    in harness: RepositoryHarness
) throws -> Int {
    try harness.store().rows(type, includingDeleted: true).count
}

private func remainingCounts(in harness: RepositoryHarness) throws -> [String: Int] {
    [
        "exercises": try count(ExerciseEntity.self, in: harness),
        "sessions": try count(WorkoutSessionEntity.self, in: harness),
        "entries": try count(ExerciseEntryEntity.self, in: harness),
        "sets": try count(SetEntryEntity.self, in: harness),
        "trainingMaxes": try count(TrainingMaxConfigEntity.self, in: harness),
        "bodyweight": try count(BodyweightEntryEntity.self, in: harness),
        "equipment": try count(EquipmentProfileEntity.self, in: harness),
        "settings": try count(UserSettingsEntity.self, in: harness),
        "records": try count(PersonalRecordCacheEntity.self, in: harness),
        "routines": try count(RoutineEntity.self, in: harness),
        "routineExercises": try count(RoutineExerciseEntity.self, in: harness),
        "targetGroups": try count(RoutineTargetGroupEntity.self, in: harness),
        "plannedTargets": try count(PlannedTargetGroupEntity.self, in: harness),
    ]
}

/// The five live columns that can name an exercise, driving one case each.
private enum ExerciseReferrer: CaseIterable {
    case entry
    case trainingMax
    case dashboard
    case variant
    case routineSlot
}
