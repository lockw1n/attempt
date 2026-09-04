import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-16.1.4`'s one-tap append: the set that follows a run, copied from the last of it.
///
/// **The assertion the requirement actually makes is about the *line*, not about the row.** "The
/// count ticks from `× 3` to `× 4`" is a claim about how the card reads afterwards, and a set that
/// was written with the right load and reps but a field the grouping compares — a rating, a
/// modifier, a note — would satisfy every field-by-field check and draw a second line. So the tests
/// below group the sets back the way the card does and assert the group, which is the only form of
/// the claim that can fail for the right reason.
@Suite("Log next set")
struct SessionNextSetTests {
    // MARK: - The write (FR-16.1.4)

    @Test("The appended set matches the group's last, and the line ticks from × 3 to × 4")
    func theCountTicks() async throws {
        let card = try await Card.withRun(of: 3)

        await card.store.logNextSet(inEntryID: card.entryID, copying: card.lastSetID)

        // The line, first — see the suite's note for why this is the assertion and not a bonus.
        let groups = SetNumbering.grouped(SetNumbering.numbered(card.store.sets))
        #expect(groups.count == 1)
        #expect(groups.first?.count == 4)
        // Then the row, which is what makes a failure of the line diagnosable.
        let appended = try #require(card.store.sets.last)
        #expect(appended.weight == Weight(grams: 100_000))
        #expect(appended.reps == 6)
        #expect(appended.rpe == 8)
        #expect(appended.modifiers == [SetModifier(.belt)])
        #expect(card.store.exercisesWriteFailure == nil)
    }

    @Test("It is written through, not only added to the list on screen — NFR-1.8")
    func theWriteReachesTheStore() async throws {
        let card = try await Card.withRun(of: 3)

        await card.store.logNextSet(inEntryID: card.entryID, copying: card.lastSetID)

        let stored = try await card.repositories.workouts.sets(
            forEntryID: card.entryID, includingDeleted: false)
        #expect(stored.count == 4)
        // Appended, and at the end of the order rather than at the count — `addSet`'s rule, which
        // this command inherits by delegating to it.
        #expect(stored.map(\.order).sorted() == [0, 1, 2, 3])
    }

    @Test("It is a completed working set — G-1.8's two flags, and the live-tracking stamp")
    func theAppendedSetIsWorkingAndCompleted() async throws {
        let card = try await Card.withRun(of: 3)

        await card.store.logNextSet(inEntryID: card.entryID, copying: card.lastSetID)

        let appended = try #require(card.store.sets.last)
        #expect(appended.isWarmup == false)
        #expect(appended.isCompleted)
        #expect(appended.completedAt != nil)
    }

    @Test("The per-set note is not carried, and the new set is therefore a line of its own")
    func theNoteIsNotCarried() async throws {
        let card = try await Card.withRun(of: 3, note: "belt on")

        await card.store.logNextSet(inEntryID: card.entryID, copying: card.lastSetID)

        let appended = try #require(card.store.sets.last)
        #expect(appended.notes.isEmpty)
        // The consequence, asserted rather than left implicit: the note is a compared field, so the
        // count does *not* tick here. Carrying it would tick it by claiming the lifter wrote
        // something they did not — see `logNextSet(inEntryID:copying:)`.
        let groups = SetNumbering.grouped(SetNumbering.numbered(card.store.sets))
        #expect(groups.map(\.count) == [3, 1])
    }

    // MARK: - What it copies from (FR-16.1.4)

    @Test("The source is re-read, so an edit landing in between is what gets copied")
    func theSourceIsReRead() async throws {
        let card = try await Card.withRun(of: 3)
        await card.store.editSet(
            id: card.lastSetID,
            inEntryID: card.entryID,
            to: SetEntryValues(weight: Weight(grams: 105_000), reps: 5, rpe: 9, isWarmup: false)
        )

        await card.store.logNextSet(inEntryID: card.entryID, copying: card.lastSetID)

        let appended = try #require(card.store.sets.last)
        #expect(appended.weight == Weight(grams: 105_000))
        #expect(appended.reps == 5)
        #expect(appended.rpe == 9)
    }

    @Test("A source that is no longer there writes nothing and reports nothing")
    func aDeletedSourceIsSilentlyNothing() async throws {
        let card = try await Card.withRun(of: 3)

        await card.store.logNextSet(inEntryID: card.entryID, copying: UUID())

        #expect(card.store.sets.count == 3)
        // Nothing on screen says so: the row went away underneath the card, and a diagnostic would
        // report a failure against a set the user can no longer see.
        #expect(card.store.exercisesWriteFailure == nil)
    }

    @Test("A workout that is not held writes nothing")
    func noWorkoutWritesNothing() async throws {
        let card = try await Card.withRun(of: 3)
        let entryID = card.entryID
        let setID = card.lastSetID
        await card.store.discard()

        await card.store.logNextSet(inEntryID: entryID, copying: setID)

        // Read including the deleted, because discarding the workout soft-deleted these three
        // (`G-1.3`) — what the assertion is about is that a fourth was not written on top of a
        // workout that is gone, and a count of live rows would read zero either way.
        let stored = try await card.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: true)
        #expect(stored.count == 3)
    }

    /// One exercise card with a run of identical working sets on it.
    private struct Card {
        let repositories: InMemoryRepositoryStack
        let store: ActiveSessionStore
        let entryID: UUID
        let lastSetID: UUID

        /// Starts a workout, puts the squat in it and logs `count` identical sets against it.
        ///
        /// 100 kg × 6 @ 8 with a belt: every field the grouping compares is set to something other
        /// than its default, so a copy that dropped one of them is visible as a split line rather
        /// than only as an absent value.
        ///
        /// - Parameters:
        ///   - count: How many sets the run holds.
        ///   - note: The per-set note each of them carries, or none.
        /// - Returns: The card.
        static func withRun(of count: Int, note: String = "") async throws -> Card {
            let workout = try await Workout.started()
            await workout.store.addExercise(id: workout.squat.id)
            let entry = try #require(workout.store.exercises.first)
            for _ in 0..<count {
                await workout.store.addSet(
                    toEntryID: entry.id,
                    values: SetEntryValues(
                        weight: Weight(grams: 100_000),
                        reps: 6,
                        rpe: 8,
                        isWarmup: false,
                        modifiers: [SetModifier(.belt)],
                        notes: note
                    )
                )
            }
            let last = try #require(workout.store.sets.last)
            return Card(
                repositories: workout.repositories,
                store: workout.store,
                entryID: entry.id,
                lastSetID: last.id
            )
        }
    }
}

extension ActiveSessionStore {
    /// The one card's sets, in the order they were logged — what nearly every assertion above reads.
    fileprivate var sets: [SetEntry] { exercises.first?.sets ?? [] }
}
