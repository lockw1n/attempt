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
}
