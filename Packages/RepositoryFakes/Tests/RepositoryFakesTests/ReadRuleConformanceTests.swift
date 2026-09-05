import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// The reads that resolve rather than enumerate, and the reads whose flag has a live half worth
/// pinning even where the deleted half is unreachable.
@Suite("Conformance — reads")
struct ReadRuleConformanceTests {
    @Test("A training max resolves to the latest entry effective on or before the date", arguments: Subject.all)
    func theLookupPicksTheLatestApplicable(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))

        // Saved newest-effective FIRST, so `updatedAt` runs opposite to `effectiveFrom`. Saved in
        // the natural order the two agree and the test passes with `effectiveFrom` dropped from the
        // key entirely — the fixture would be satisfying the property under test.
        for (days, grams) in [(3.0, 170_000), (1.0, 160_000), (0.0, 150_000)] {
            try await repositories.trainingMaxes.save(
                trainingMaxHistoryRecord(
                    exerciseID: exerciseID,
                    effectiveFrom: fixtureCreatedAt + days * fixtureDay,
                    grams: grams))
        }

        #expect(
            try await repositories.trainingMaxes.trainingMax(
                forExerciseID: exerciseID, on: fixtureCreatedAt - fixtureDay) == nil)
        #expect(
            try await repositories.trainingMaxes.trainingMax(
                forExerciseID: exerciseID, on: fixtureCreatedAt)?.newWeight
                == Weight(grams: 150_000))
        #expect(
            try await repositories.trainingMaxes.trainingMax(
                forExerciseID: exerciseID, on: fixtureCreatedAt + 2 * fixtureDay)?.newWeight
                == Weight(grams: 160_000))
        #expect(
            try await repositories.trainingMaxes.trainingMax(
                forExerciseID: exerciseID, on: fixtureCreatedAt + 9 * fixtureDay)?.newWeight
                == Weight(grams: 170_000))
    }

    /// The *other* in-force lookup, and it needs its own case rather than riding on the one above.
    ///
    /// `TrainingMaxRepository` resolves two tables the same way and the two resolutions are separate
    /// code in both implementations — so a single test over the history leaves the configuration's
    /// `<=` unprobed in each. Measured: narrowing the configuration predicate to `<` left every
    /// suite in this package and in `Persistence` green.
    @Test(
        "A training-max configuration resolves to the latest entry effective on or before the date",
        arguments: Subject.all)
    func theConfigurationLookupPicksTheLatestApplicable(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))

        // Saved newest-effective FIRST, for `theLookupPicksTheLatestApplicable`'s reason: saved in
        // the natural order `updatedAt` agrees with `effectiveFrom` and the lookup passes with
        // `effectiveFrom` dropped from the key entirely.
        for (days, percentage) in [(3.0, 0.95), (1.0, 0.90), (0.0, 0.85)] {
            try await repositories.trainingMaxes.saveConfiguration(
                trainingMaxRecord(
                    exerciseID: exerciseID,
                    effectiveFrom: fixtureCreatedAt + days * fixtureDay,
                    percentage: percentage))
        }

        // The middle assertion is the probe: `on: fixtureCreatedAt` sits exactly on the first
        // entry's effective date, so `<` in place of `<=` falls through to nothing here.
        #expect(
            try await repositories.trainingMaxes.configuration(
                forExerciseID: exerciseID, on: fixtureCreatedAt - fixtureDay) == nil)
        #expect(
            try await repositories.trainingMaxes.configuration(
                forExerciseID: exerciseID, on: fixtureCreatedAt)?.percentage == 0.85)
        #expect(
            try await repositories.trainingMaxes.configuration(
                forExerciseID: exerciseID, on: fixtureCreatedAt + 2 * fixtureDay)?.percentage
                == 0.90)
        #expect(
            try await repositories.trainingMaxes.configuration(
                forExerciseID: exerciseID, on: fixtureCreatedAt + 9 * fixtureDay)?.percentage
                == 0.95)
    }

    @Test("Saving a configuration appends rather than replacing the one it supersedes", arguments: Subject.all)
    func theConfigurationHistoryIsKept(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        try await repositories.trainingMaxes.saveConfiguration(
            trainingMaxRecord(
                exerciseID: exerciseID, effectiveFrom: fixtureCreatedAt, percentage: 0.85))
        try await repositories.trainingMaxes.saveConfiguration(
            trainingMaxRecord(
                exerciseID: exerciseID,
                effectiveFrom: fixtureCreatedAt + fixtureDay,
                percentage: 0.95))

        let history = try await repositories.trainingMaxes.configurationHistory(
            forExerciseID: exerciseID, includingDeleted: false)

        #expect(history.map(\.percentage) == [0.95, 0.85])
    }

    @Test("Saving a training max appends rather than replacing the one it supersedes", arguments: Subject.all)
    func theHistoryIsKept(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        try await repositories.trainingMaxes.save(
            trainingMaxHistoryRecord(
                exerciseID: exerciseID, effectiveFrom: fixtureCreatedAt, grams: 150_000))
        try await repositories.trainingMaxes.save(
            trainingMaxHistoryRecord(
                exerciseID: exerciseID,
                effectiveFrom: fixtureCreatedAt + fixtureDay,
                grams: 160_000))

        let history = try await repositories.trainingMaxes.history(
            forExerciseID: exerciseID, includingDeleted: false)

        #expect(history.map(\.newWeight) == [Weight(grams: 160_000), Weight(grams: 150_000)])
    }

    @Test("A training-max read answers for one exercise only", arguments: Subject.all)
    func theLookupIsScopedToItsExercise(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let mine = UUID()
        let theirs = UUID()
        try await repositories.exercises.save(exerciseRecord(id: mine, name: "Squat"))
        try await repositories.exercises.save(exerciseRecord(id: theirs, name: "Bench Press"))
        try await repositories.trainingMaxes.save(
            trainingMaxHistoryRecord(exerciseID: theirs, effectiveFrom: fixtureCreatedAt, grams: 120_000))

        try await repositories.trainingMaxes.saveConfiguration(
            trainingMaxRecord(exerciseID: theirs, effectiveFrom: fixtureCreatedAt, percentage: 0.85))

        #expect(
            try await repositories.trainingMaxes.trainingMax(
                forExerciseID: mine, on: fixtureCreatedAt + fixtureDay) == nil)
        #expect(
            try await repositories.trainingMaxes.history(
                forExerciseID: mine, includingDeleted: true
            ).isEmpty)
        #expect(
            try await repositories.trainingMaxes.configuration(
                forExerciseID: mine, on: fixtureCreatedAt + fixtureDay) == nil)
        #expect(
            try await repositories.trainingMaxes.configurationHistory(
                forExerciseID: mine, includingDeleted: true
            ).isEmpty)
        // Anchored: four absences are also what an empty store reads, so the rows the other
        // exercise does hold are what make this a claim about scoping.
        #expect(
            try await repositories.trainingMaxes.history(
                forExerciseID: theirs, includingDeleted: true
            ).count == 1)
        #expect(
            try await repositories.trainingMaxes.configurationHistory(
                forExerciseID: theirs, includingDeleted: true
            ).count == 1)
    }

    @Test("Archived exercises are listed — filtering them is the caller's", arguments: Subject.all)
    func archivedExercisesAreListed(_ subject: Subject) async throws {
        let repositories = try subject.make()
        try await repositories.exercises.save(exerciseRecord(name: "Squat"))
        try await repositories.exercises.save(
            exerciseRecord(name: "Behind-the-neck press", isArchived: true))

        let read = try await repositories.exercises.exercises(includingDeleted: false)

        // `FR-1.1.5` distinguishes archived from deleted: an archived exercise leaves the picker,
        // not the store, and a repository that conflated the two would hide logged history.
        #expect(read.count == 2)
        #expect(read.contains { $0.isArchived })
    }

    /// The reachable half of the `includingDeleted:` flag on the families no protocol deletes.
    ///
    /// Nothing soft-deletes an exercise or a training-max *configuration*, so for those the flag's
    /// deleted half cannot be reached from here at all — see the suite's header. What is reachable
    /// is that neither value of the flag hides a live row, which a fake wiring the flag backwards
    /// would fail. The history's deleted half *is* reachable, through
    /// `TrainingMaxRepository.deleteEntry(id:)`, and `SoftDeleteConformanceTests` is where it is
    /// held.
    @Test("Neither value of the flag hides a live row", arguments: Subject.all)
    func theFlagNeverHidesALiveRow(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        try await repositories.trainingMaxes.save(
            trainingMaxHistoryRecord(exerciseID: exerciseID, effectiveFrom: fixtureCreatedAt))
        try await repositories.trainingMaxes.saveConfiguration(
            trainingMaxRecord(exerciseID: exerciseID, effectiveFrom: fixtureCreatedAt))

        for flag in [true, false] {
            #expect(try await repositories.exercises.exercises(includingDeleted: flag).count == 1)
            #expect(
                try await repositories.exercises.exercise(id: exerciseID, includingDeleted: flag)
                    != nil)
            #expect(
                try await repositories.trainingMaxes.history(
                    forExerciseID: exerciseID, includingDeleted: flag
                ).count == 1)
            #expect(
                try await repositories.trainingMaxes.configurationHistory(
                    forExerciseID: exerciseID, includingDeleted: flag
                ).count == 1)
        }
    }

    /// The five repositories are five objects over one store, and a caller's test depends on it
    /// without ever saying so — an entry names an exercise that a *different* repository saved.
    @Test("The five repositories see each other's writes", arguments: Subject.all)
    func theRepositoriesShareTheStore(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        let sessionID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        try await repositories.workouts.save(sessionRecord(id: sessionID))

        // Refused as dangling if the workout side could not see the exercise side's write.
        try await repositories.workouts.save(
            entryRecord(sessionID: sessionID, exerciseID: exerciseID))

        #expect(
            try await repositories.workouts.entries(
                forSessionID: sessionID, includingDeleted: false
            ).count == 1)
    }

    /// Added because a probe survived without it: dropping the `sessionID` clause from
    /// `entries(forSessionID:)` changed no answer, since every fixture with two sessions read the
    /// feed rather than the entries. **A scoped read needs a second scope in the store**, or it is
    /// asserting that the rows exist rather than that the scope was applied.
    @Test("A read scoped to a parent returns that parent's rows and no others", arguments: Subject.all)
    func aScopedReadIsScoped(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let mine = try await repositories.timeline()
        let theirs = try await repositories.timeline()
        let mySet = UUID()
        try await repositories.workouts.save(setRecord(id: mySet, entryID: mine.entryID))
        try await repositories.workouts.save(setRecord(entryID: theirs.entryID))

        #expect(
            try await repositories.workouts.entries(
                forSessionID: mine.sessionID, includingDeleted: true
            ).map(\.id) == [mine.entryID])
        #expect(
            try await repositories.workouts.sets(
                forEntryID: mine.entryID, includingDeleted: true
            ).map(\.id) == [mySet])
    }

    @Test("An empty store answers empty rather than throwing", arguments: Subject.all)
    func anEmptyStoreIsNotAnError(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let range = fixtureCreatedAt...(fixtureCreatedAt + fixtureDay)

        #expect(try await repositories.exercises.exercises(includingDeleted: true).isEmpty)
        #expect(try await repositories.workouts.sessions(in: range, includingDeleted: true).isEmpty)
        #expect(try await repositories.bodyweight.entries(in: range, includingDeleted: true).isEmpty)
        #expect(try await repositories.equipment.profiles(includingDeleted: true).isEmpty)
        #expect(
            try await repositories.workouts.entries(
                forSessionID: UUID(), includingDeleted: true
            ).isEmpty)
        #expect(
            try await repositories.workouts.sets(forEntryID: UUID(), includingDeleted: true)
                .isEmpty)
    }
}
