import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// Rule 1 and rule 3 of the `RepositoryInterface` header: reads return live rows, deletion is soft,
/// and a soft delete cascades downwards and never upwards (`G-1.3`).
@Suite("Conformance — soft delete and the cascade")
struct SoftDeleteConformanceTests {
    @Test("A deleted row leaves the default read and is still there behind the flag", arguments: Subject.all)
    func aDeleteIsSoft(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        try await repositories.bodyweight.save(bodyweightRecord(id: id, grams: 80_000))

        try await repositories.bodyweight.deleteEntry(id: id)

        #expect(try await repositories.bodyweight.entry(id: id, includingDeleted: false) == nil)
        let kept = try #require(
            try await repositories.bodyweight.entry(id: id, includingDeleted: true))
        #expect(kept.deletedAt != nil)
        #expect(kept.weight == Weight(grams: 80_000))

        // **A delete is a write, so it stamps.** `updatedAt` is `G-2.4`'s conflict key: a delete
        // that left it describing the previous write would lose to a remote edit and the row would
        // come back. Asserted as an equality rather than as "it moved" — the delete stamps both
        // columns from one instant, which is exact and has no timing in it.
        #expect(kept.updatedAt == kept.deletedAt)
    }

    /// **Every by-id read whose row a protocol can delete, not just the one above.**
    ///
    /// Covering this on `bodyweight` alone left probes alive on `session(id:)` and `profile(id:)`:
    /// both could return a soft-deleted row with the whole suite green, and `Persistence`'s own
    /// tests pin them, so the drift would have been one-sided and invisible exactly here.
    /// `exercise(id:)` is absent on purpose — nothing in `ExerciseRepository` deletes, so the
    /// deleted half of its flag is unreachable; the suite header records that as exclusion 4 and
    /// `theFlagNeverHidesALiveRow` asserts the half that is reachable.
    @Test("Every by-id read hides its deleted row and the flag brings it back", arguments: Subject.all)
    func theByIDReadsAllHonourTheFlag(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        let profileID = UUID()
        let weightID = UUID()
        try await repositories.equipment.save(profileRecord(id: profileID))
        try await repositories.bodyweight.save(bodyweightRecord(id: weightID))

        try await repositories.workouts.deleteSession(id: timeline.sessionID)
        try await repositories.equipment.deleteProfile(id: profileID)
        try await repositories.bodyweight.deleteEntry(id: weightID)

        #expect(
            try await repositories.workouts.session(
                id: timeline.sessionID, includingDeleted: false) == nil)
        #expect(
            try await repositories.equipment.profile(id: profileID, includingDeleted: false) == nil)
        #expect(
            try await repositories.bodyweight.entry(id: weightID, includingDeleted: false) == nil)

        // Both halves, so the test cannot be satisfied by a read that answers `nil` regardless.
        #expect(
            try await repositories.workouts.session(
                id: timeline.sessionID, includingDeleted: true) != nil)
        #expect(
            try await repositories.equipment.profile(id: profileID, includingDeleted: true) != nil)
        #expect(
            try await repositories.bodyweight.entry(id: weightID, includingDeleted: true) != nil)
    }

    @Test("An enumerating read drops the deleted row and the flag brings it back", arguments: Subject.all)
    func theFlagDecidesWhatAListReturns(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let range = fixtureCreatedAt...(fixtureCreatedAt + fixtureDay)
        let deleted = UUID()
        try await repositories.bodyweight.save(bodyweightRecord(id: deleted, grams: 80_000))
        try await repositories.bodyweight.save(
            bodyweightRecord(date: fixtureCreatedAt + fixtureDay, grams: 81_000))
        try await repositories.bodyweight.deleteEntry(id: deleted)

        let live = try await repositories.bodyweight.entries(in: range, includingDeleted: false)
        let all = try await repositories.bodyweight.entries(in: range, includingDeleted: true)

        #expect(live.map(\.weight) == [Weight(grams: 81_000)])
        #expect(all.count == 2)
    }

    /// **All five deletes, not one.** Covering this on `bodyweight` alone left a probe alive on
    /// `deleteExerciseEntry`: "a deleted row is not there to delete" is the kind of rule that gets
    /// implemented for the members somebody happened to think of.
    @Test("A second delete of the same row is refused — it is no longer there", arguments: Subject.all)
    func aDeletedRowIsNotThereToDelete(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        try await repositories.bodyweight.save(bodyweightRecord(id: id))
        try await repositories.bodyweight.deleteEntry(id: id)
        let deletedAt = try #require(
            try await repositories.bodyweight.entry(id: id, includingDeleted: true)?.deletedAt)

        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.bodyweight.deleteEntry(id: id)
        }

        // …and the refusal left the row exactly as it was: a second delete that restamped would
        // move `updatedAt`, which is G-2.4's conflict key, for a write that did not happen.
        let after = try #require(
            try await repositories.bodyweight.entry(id: id, includingDeleted: true))
        #expect(after.deletedAt == deletedAt)

        let profileID = UUID()
        try await repositories.equipment.save(profileRecord(id: profileID))
        try await repositories.equipment.deleteProfile(id: profileID)
        await #expect(throws: RepositoryError.recordNotFound(id: profileID)) {
            try await repositories.equipment.deleteProfile(id: profileID)
        }

        // The three workout deletes, each on a row its own delete put in that state — and the
        // set is deleted by the entry's cascade rather than by `deleteSet`, so the refusal has to
        // hold for a row this call never saw.
        let timeline = try await repositories.timeline()
        let setID = UUID()
        try await repositories.workouts.save(setRecord(id: setID, entryID: timeline.entryID))
        try await repositories.workouts.deleteExerciseEntry(id: timeline.entryID)
        await #expect(throws: RepositoryError.recordNotFound(id: timeline.entryID)) {
            try await repositories.workouts.deleteExerciseEntry(id: timeline.entryID)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: setID)) {
            try await repositories.workouts.deleteSet(id: setID)
        }
        try await repositories.workouts.deleteSession(id: timeline.sessionID)
        await #expect(throws: RepositoryError.recordNotFound(id: timeline.sessionID)) {
            try await repositories.workouts.deleteSession(id: timeline.sessionID)
        }
    }

    @Test("Deleting a session sweeps its entries and their sets", arguments: Subject.all)
    func theSessionCascadeReachesTheSets(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        let setID = UUID()
        try await repositories.workouts.save(setRecord(id: setID, entryID: timeline.entryID))

        try await repositories.workouts.deleteSession(id: timeline.sessionID)

        #expect(
            try await repositories.workouts.entries(
                forSessionID: timeline.sessionID, includingDeleted: false
            ).isEmpty)
        #expect(
            try await repositories.workouts.sets(
                forEntryID: timeline.entryID, includingDeleted: false
            ).isEmpty)
        let sweptSet = try #require(
            try await repositories.workouts.sets(
                forEntryID: timeline.entryID, includingDeleted: true
            ).first)
        #expect(sweptSet.deletedAt != nil)

        // One write, so one instant: the session, its entry and its set all left the user's history
        // at the same moment, and each of the three was stamped by it.
        let sweptSession = try #require(
            try await repositories.workouts.session(
                id: timeline.sessionID, includingDeleted: true))
        let sweptEntry = try #require(
            try await repositories.workouts.entries(
                forSessionID: timeline.sessionID, includingDeleted: true
            ).first)
        #expect(sweptSession.updatedAt == sweptSession.deletedAt)
        #expect(sweptEntry.deletedAt == sweptSession.deletedAt)
        #expect(sweptEntry.updatedAt == sweptSession.deletedAt)
        #expect(sweptSet.deletedAt == sweptSession.deletedAt)
        #expect(sweptSet.updatedAt == sweptSession.deletedAt)
    }

    @Test("Deleting an entry sweeps its sets and leaves the session alone", arguments: Subject.all)
    func theEntryCascadeNeverGoesUpwards(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        try await repositories.workouts.save(setRecord(entryID: timeline.entryID))

        try await repositories.workouts.deleteExerciseEntry(id: timeline.entryID)

        #expect(
            try await repositories.workouts.sets(
                forEntryID: timeline.entryID, includingDeleted: false
            ).isEmpty)
        #expect(
            try await repositories.workouts.session(
                id: timeline.sessionID, includingDeleted: false) != nil)
    }

    @Test("Deleting a set touches nothing else", arguments: Subject.all)
    func aSetDeleteIsLocal(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        let doomed = UUID()
        try await repositories.workouts.save(setRecord(id: doomed, entryID: timeline.entryID))
        try await repositories.workouts.save(
            setRecord(entryID: timeline.entryID, order: 1, grams: 110_000))

        try await repositories.workouts.deleteSet(id: doomed)

        let remaining = try await repositories.workouts.sets(
            forEntryID: timeline.entryID, includingDeleted: false)
        #expect(remaining.map(\.weight) == [Weight(grams: 110_000)])
        let entries = try await repositories.workouts.entries(
            forSessionID: timeline.sessionID, includingDeleted: false)
        #expect(entries.count == 1)
    }

    /// The state the brief called "a live set under a deleted entry", built through the front door.
    ///
    /// Saving into a soft-deleted entry is legal — a soft-deleted target is not a dangling
    /// reference — so no seeding is needed to reach the case, and both subjects have to produce it.
    /// Rule 3's promise is that nothing under a deleted session stays readable, so a cascade that
    /// stopped at live entries would leave this set live.
    @Test("The session cascade reaches through an entry that was already deleted", arguments: Subject.all)
    func theCascadeReachesThroughADeletedEntry(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        try await repositories.workouts.deleteExerciseEntry(id: timeline.entryID)
        let deletedEntry = try #require(
            try await repositories.workouts.entries(
                forSessionID: timeline.sessionID, includingDeleted: true
            ).first)

        let stranded = UUID()
        try await repositories.workouts.save(setRecord(id: stranded, entryID: timeline.entryID))
        #expect(
            try await repositories.workouts.sets(
                forEntryID: timeline.entryID, includingDeleted: false
            ).map(\.id) == [stranded])

        try await repositories.workouts.deleteSession(id: timeline.sessionID)

        #expect(
            try await repositories.workouts.sets(
                forEntryID: timeline.entryID, includingDeleted: false
            ).isEmpty)

        // The entry itself was not restamped. `deletedAt` records when it left the user's history
        // and `updatedAt` is G-2.4's conflict key; the cascade swept its set, not it.
        let after = try #require(
            try await repositories.workouts.entries(
                forSessionID: timeline.sessionID, includingDeleted: true
            ).first)
        #expect(after.deletedAt == deletedEntry.deletedAt)
        #expect(after.updatedAt == deletedEntry.updatedAt)
    }

    /// The feed's own half of rule 1, and it has two independent clauses — a probe survived on each
    /// of them separately, because every other feed test asked for `includingDeleted: true`.
    ///
    /// The stakes are `FR-1.2.12`: this list is what `PersonalRecordCalculator` is handed, so a set
    /// the user discarded that stayed in it becomes a personal record from a workout that did not
    /// happen.
    @Test("The feed excludes a deleted set and a deleted entry's live set", arguments: Subject.all)
    func theFeedHonoursTheFlagOnBothLevels(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        let kept = try await repositories.timeline(exerciseID: exerciseID, entryOrder: 0)
        let doomedEntry = try await repositories.timeline(
            exerciseID: exerciseID, sessionID: kept.sessionID, entryOrder: 1)

        try await repositories.workouts.save(setRecord(entryID: kept.entryID, grams: 100_000))
        let deletedSet = UUID()
        try await repositories.workouts.save(
            setRecord(id: deletedSet, entryID: kept.entryID, order: 1, grams: 110_000))
        try await repositories.workouts.deleteSet(id: deletedSet)

        // A LIVE set under a DELETED entry — the state that separates the two clauses. Without it,
        // the cascade would have deleted this set too and the set-level filter alone would explain
        // the answer.
        try await repositories.workouts.deleteExerciseEntry(id: doomedEntry.entryID)
        try await repositories.workouts.save(
            setRecord(entryID: doomedEntry.entryID, grams: 120_000))

        let live = try await repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: false)
        let all = try await repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: true)

        #expect(live.map(\.weight) == [Weight(grams: 100_000)])
        #expect(all.count == 3)
    }

    @Test("A deleted session still supplies its date to the personal-record feed", arguments: Subject.all)
    func aDeletedSessionStillSuppliesItsDate(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()

        // The EARLIER session is the one deleted, so an implementation that lost its date — and
        // sorted its entry last — would give a different order rather than the same one.
        let earlier = try await repositories.timeline(
            exerciseID: exerciseID, date: fixtureCreatedAt)
        let later = try await repositories.timeline(
            exerciseID: exerciseID, date: fixtureCreatedAt + fixtureDay)
        try await repositories.workouts.save(
            setRecord(entryID: earlier.entryID, grams: 100_000))
        try await repositories.workouts.save(setRecord(entryID: later.entryID, grams: 110_000))
        try await repositories.workouts.deleteSession(id: earlier.sessionID)

        // The cascade deleted the earlier entry and its set, so the earlier one is only visible
        // behind the flag — which is the read that has to keep it in front.
        let feed = try await repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: true)

        #expect(feed.map(\.weight) == [Weight(grams: 100_000), Weight(grams: 110_000)])
    }
}
