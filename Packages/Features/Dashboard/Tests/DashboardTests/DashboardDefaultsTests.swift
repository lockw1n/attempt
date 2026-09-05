import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-1.9.1`'s "squat, bench, deadlift", resolved against a catalogue rather than against three
/// stored identifiers.
@MainActor
@Suite("Dashboard default tiles")
struct DashboardDefaultsTests {
    @Test("The three competition lifts are chosen, in the requirement's order")
    func thethreeCompetitionLiftsAreChosen() async throws {
        let fixture = DashboardFixture()
        let bench = try await fixture.exercise(named: "Bench Press", movement: .bench)
        let deadlift = try await fixture.exercise(named: "Deadlift", movement: .deadlift)
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)

        let chosen = DashboardDefaults.exerciseIDs(
            in: try await fixture.repositories.exercises.exercises(includingDeleted: false))

        #expect(chosen == [squat, bench, deadlift])
    }

    /// The clauses that tell a competition lift from the rest of its movement: the leg press is a
    /// squat and the hip thrust a deadlift, and neither is what the requirement names.
    @Test("A movement's machine and bodyweight work is not the default")
    func amovementsAccessoryWorkIsNotTheDefault() async throws {
        let fixture = DashboardFixture()
        try await fixture.exercise(named: "Ab Machine Squat", movement: .squat, equipment: .machine)
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)

        let chosen = DashboardDefaults.exerciseIDs(
            in: try await fixture.repositories.exercises.exercises(includingDeleted: false))

        #expect(chosen == [squat])
    }

    @Test("A variation is not the default; its parent is")
    func avariationIsNotTheDefault() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.exercise(
            named: "A Low-Bar Back Squat", movement: .squat, parentExerciseID: squat)

        let chosen = DashboardDefaults.exerciseIDs(
            in: try await fixture.repositories.exercises.exercises(includingDeleted: false))

        #expect(chosen == [squat])
    }

    @Test("A custom or archived exercise is never a default")
    func acustomOrArchivedExerciseIsNeverADefault() async throws {
        let fixture = DashboardFixture()
        try await fixture.exercise(named: "AA Custom Squat", movement: .squat, isCustom: true)
        try await fixture.exercise(named: "AB Old Squat", movement: .squat, isArchived: true)
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)

        let chosen = DashboardDefaults.exerciseIDs(
            in: try await fixture.repositories.exercises.exercises(includingDeleted: false))

        #expect(chosen == [squat])
    }

    /// A lifter who deleted the barbell bench press gets two tiles, not a tile naming a row that is
    /// not there.
    @Test("A movement with no candidate is simply absent")
    func amovementWithNoCandidateIsAbsent() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)

        let chosen = DashboardDefaults.exerciseIDs(
            in: try await fixture.repositories.exercises.exercises(includingDeleted: false))

        #expect(chosen == [squat])
    }

    /// The tiebreak is a rule rather than a claim, and what it buys is that the same lifter sees the
    /// same tile on every launch.
    @Test("Several candidates for one movement resolve to the same one every time")
    func severalCandidatesResolveStably() async throws {
        let fixture = DashboardFixture()
        let deadlift = try await fixture.exercise(named: "Deadlift", movement: .deadlift)
        try await fixture.exercise(named: "Good Morning", movement: .deadlift)
        try await fixture.exercise(named: "Hip Thrust", movement: .deadlift)

        let catalogue = try await fixture.repositories.exercises.exercises(includingDeleted: false)
        #expect(DashboardDefaults.exerciseIDs(in: catalogue) == [deadlift])
        #expect(DashboardDefaults.exerciseIDs(in: catalogue.reversed()) == [deadlift])
    }

    // MARK: - FR-16.5.1: a default with no history is replaced

    /// Review finding 04, as a test: the log holds bench pressing and no barbell squat or deadlift,
    /// so two of the three tiles were full empty-state blocks headed by lifts nobody performs.
    @Test("A default lift with no history is replaced by what the lifter actually trains")
    func adefaultWithNoHistoryIsReplaced() async throws {
        let fixture = DashboardFixture()
        let bench = try await fixture.exercise(named: "Bench Press", movement: .bench)
        try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.exercise(named: "Deadlift", movement: .deadlift)
        let chins = try await fixture.exercise(
            named: "Chin-Up", movement: .row, equipment: .bodyweight)
        let curls = try await fixture.exercise(
            named: "Dumbbell Curl", movement: .row, equipment: .dumbbell)

        let chosen = DashboardDefaults.exerciseIDs(
            in: try await fixture.repositories.exercises.exercises(includingDeleted: false),
            mostTrained: [bench, chins, curls])

        // The bench keeps its own slot — it has history — and the squat and deadlift slots take the
        // trained exercises in rank order. Nothing is filtered: a chin-up is neither a barbell lift
        // nor a competition one, and it is what this lifter does.
        #expect(chosen == [chins, bench, curls])
    }

    /// The store the app launches into. A ranking cannot replace anything here, and three named
    /// tiles with no numbers yet is a better first screen than no tiles at all.
    @Test("With nothing trained the seeded three stand, replaced by nothing")
    func withNothingTrainedTheSeededThreeStand() async throws {
        let fixture = DashboardFixture()
        let bench = try await fixture.exercise(named: "Bench Press", movement: .bench)
        let deadlift = try await fixture.exercise(named: "Deadlift", movement: .deadlift)
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)

        let chosen = DashboardDefaults.exerciseIDs(
            in: try await fixture.repositories.exercises.exercises(includingDeleted: false),
            mostTrained: [])

        #expect(chosen == [squat, bench, deadlift])
    }

    /// The trap the reservation exists for: the most-trained exercise is also a *later* movement's
    /// own candidate, so filling the squat's gap with it would tile the bench press twice.
    @Test("A replacement never takes a slot another default is about to keep")
    func areplacementNeverDuplicatesAKeptDefault() async throws {
        let fixture = DashboardFixture()
        let bench = try await fixture.exercise(named: "Bench Press", movement: .bench)
        try await fixture.exercise(named: "Back Squat", movement: .squat)
        let rows = try await fixture.exercise(
            named: "Barbell Row", movement: .row, equipment: .barbell)

        let chosen = DashboardDefaults.exerciseIDs(
            in: try await fixture.repositories.exercises.exercises(includingDeleted: false),
            mostTrained: [bench, rows])

        #expect(chosen == [rows, bench])
    }

    /// Archiving is how an exercise leaves the pickers (`FR-1.1.5`), and a tile is a picker's
    /// output — so a lift trained often and then retired is not what a gap is filled with.
    @Test("An archived exercise is never a replacement, however often it was trained")
    func anarchivedExerciseIsNeverAReplacement() async throws {
        let fixture = DashboardFixture()
        try await fixture.exercise(named: "Back Squat", movement: .squat)
        let retired = try await fixture.exercise(
            named: "Old Machine Press", movement: .other, equipment: .machine, isArchived: true)
        let dips = try await fixture.exercise(
            named: "Dip", movement: .other, equipment: .bodyweight)

        let chosen = DashboardDefaults.exerciseIDs(
            in: try await fixture.repositories.exercises.exercises(includingDeleted: false),
            mostTrained: [retired, dips])

        #expect(chosen == [dips])
    }
}
