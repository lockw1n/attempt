import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

// TR-1.14, G-1.3 for the program chain. Split from `StorePurgeTests` for `RoutinePurgeTests`'
// reason; the seeding rationale in that suite's header applies here unchanged.

@Suite("Store purge — programs")
struct ProgramPurgeTests {
    private let longAgo = Date(timeIntervalSince1970: 1_000_000)
    private let cutoff = Date(timeIntervalSince1970: 1_500_000)

    private func softDeleted<T: StoredEntity>(_ row: T, at when: Date) -> T {
        row.deletedAt = when
        return row
    }

    private func count<T: StoredEntity>(
        _ type: T.Type,
        in harness: RepositoryHarness
    ) throws -> Int {
        try harness.store().rows(type, includingDeleted: true).count
    }

    // The program chain's retention, which is transitive over three hops and crosses into the
    // routine chain: a live session holds its run, the run holds its program, and that program's
    // live day holds the routine it names. Every row above the session is deleted, so a
    // single-pass plan in the wrong order would free one of them.
    @Test("A live session holds its run, its program and the routine that program's day names")
    func programChainRetainsTransitively() async throws {
        let harness = try RepositoryHarness()
        let routine = softDeleted(RoutineEntity(name: "Squat day"), at: longAgo)
        let program = softDeleted(ProgramEntity(name: "#2", notes: "14.09.25"), at: longAgo)
        let day = ProgramDayEntity(programID: program.id, routineID: routine.id, order: 0)
        let run = softDeleted(
            ProgramRunEntity(
                programID: program.id, startedAt: longAgo, weekNumber: 2, nextDayIndex: 1),
            at: longAgo)
        try harness.seed([
            routine,
            program,
            day,
            run,
            WorkoutSessionEntity(date: longAgo, programRunID: run.id),
        ])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        // Three rows held back: the run, the program, and the routine the live day names.
        #expect(report.removed == 0)
        #expect(report.retained == 3)
        #expect(try count(ProgramRunEntity.self, in: harness) == 1)
        #expect(try count(ProgramEntity.self, in: harness) == 1)
        #expect(try count(RoutineEntity.self, in: harness) == 1)
    }

    // The other direction: with nothing live above it, the whole chain is free in one pass. Without
    // this the test above would pass for a plan that simply never frees a program row.
    @Test("A wholly deleted program chain is removed")
    func deletedProgramChainGoesWhole() async throws {
        let harness = try RepositoryHarness()
        let program = softDeleted(ProgramEntity(name: "#2", notes: ""), at: longAgo)
        let routine = softDeleted(RoutineEntity(name: "Squat day"), at: longAgo)
        try harness.seed([
            program,
            routine,
            softDeleted(
                ProgramDayEntity(programID: program.id, routineID: routine.id, order: 0),
                at: longAgo),
            softDeleted(
                ProgramRunEntity(
                    programID: program.id, startedAt: longAgo, weekNumber: 2, nextDayIndex: 1),
                at: longAgo),
        ])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 4)
        #expect(report.retained == 0)
        #expect(try count(ProgramEntity.self, in: harness) == 0)
        #expect(try count(ProgramDayEntity.self, in: harness) == 0)
        #expect(try count(ProgramRunEntity.self, in: harness) == 0)
        #expect(try count(RoutineEntity.self, in: harness) == 0)
    }

    // A session logged outside a program names no run, so it holds nothing back. The column is
    // optional and a plan that read it unconditionally would either crash or retain the sentinel.
    @Test("A session with no run holds no program row back")
    func aSessionOutsideAProgramRetainsNothing() async throws {
        let harness = try RepositoryHarness()
        let program = softDeleted(ProgramEntity(name: "#2", notes: ""), at: longAgo)
        try harness.seed([
            program,
            softDeleted(
                ProgramRunEntity(
                    programID: program.id, startedAt: longAgo, weekNumber: 2, nextDayIndex: 1),
                at: longAgo),
            WorkoutSessionEntity(date: longAgo),
        ])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 2)
        #expect(report.retained == 0)
        #expect(try count(ProgramEntity.self, in: harness) == 0)
        #expect(try count(ProgramRunEntity.self, in: harness) == 0)
        // The session itself is live and stays, which is what says the two removals above are the
        // program rows rather than everything.
        #expect(try count(WorkoutSessionEntity.self, in: harness) == 1)
    }
}
