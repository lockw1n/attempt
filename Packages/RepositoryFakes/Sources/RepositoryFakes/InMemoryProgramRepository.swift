import Foundation
import RepositoryInterface

/// `ProgramRepository` over three dictionaries (`TR-0.4.2`, `TR-16.2`).
///
/// A facade: the rules are on ``InMemoryRepositoryStore`` below, because a day's save checks a table
/// the routine repository owns.
struct InMemoryProgramRepository: ProgramRepository, Sendable {
    let store: InMemoryRepositoryStore

    /// Every program, by name then id.
    func programs(includingDeleted: Bool) async throws -> [Program] {
        await store.programList(includingDeleted: includingDeleted)
    }

    /// One program, or `nil`.
    func program(id: UUID, includingDeleted: Bool) async throws -> Program? {
        await store.program(id: id, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the program.
    func save(_ program: Program) async throws {
        await store.saveProgram(program)
    }

    /// Soft-deletes the program, its days and its runs.
    func deleteProgram(id: UUID) async throws {
        try await store.deleteProgram(id: id)
    }

    /// The program's days, in order.
    func days(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramDay] {
        await store.programDays(forProgramID: programID, includingDeleted: includingDeleted)
    }

    /// One day, or `nil`.
    func programDay(id: UUID, includingDeleted: Bool) async throws -> ProgramDay? {
        await store.programDay(id: id, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the day, refusing one whose program or routine does not exist.
    func save(_ day: ProgramDay) async throws {
        try await store.saveProgramDay(day)
    }

    /// Soft-deletes one day.
    func deleteDay(id: UUID) async throws {
        try await store.deleteProgramDay(id: id)
    }

    /// The open run, or `nil`.
    func currentRun() async throws -> ProgramRun? {
        await store.currentProgramRun()
    }

    /// Every pass through the program, newest start first.
    func runs(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramRun] {
        await store.programRuns(forProgramID: programID, includingDeleted: includingDeleted)
    }

    /// One run, or `nil`.
    func run(id: UUID, includingDeleted: Bool) async throws -> ProgramRun? {
        await store.programRun(id: id, includingDeleted: includingDeleted)
    }

    /// Opens the run and closes every other open one.
    func startRun(_ run: ProgramRun) async throws {
        try await store.startProgramRun(run)
    }

    /// Inserts or replaces the run, touching no other row.
    func save(_ run: ProgramRun) async throws {
        try await store.saveProgramRun(run)
    }

    /// Soft-deletes one run.
    func deleteRun(id: UUID) async throws {
        try await store.deleteProgramRun(id: id)
    }
}

extension InMemoryRepositoryStore {
    /// Every program, by name then id.
    func programList(includingDeleted: Bool) -> [Program] {
        programs.values
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.name, $0.id.uuidString) }
    }

    /// One program, subject to rule 1.
    func program(id: UUID, includingDeleted: Bool) -> Program? {
        programs[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// Inserts or replaces a program.
    func saveProgram(_ program: Program) {
        upserted(program, into: &programs, at: .now)
    }

    /// Soft-deletes a program, its days and its runs.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live program
    ///   carries `id`.
    func deleteProgram(id: UUID) throws {
        let now = Date.now
        try softDelete(id: id, in: &programs, at: now)
        for day in programDays.values where day.programID == id {
            programDays[day.id] = sweeping(day, at: now)
        }
        for run in programRuns.values where run.programID == id {
            programRuns[run.id] = sweeping(run, at: now)
        }
    }

    /// The program's days, in order — an archived routine is not this read's refusal to make.
    func programDays(forProgramID programID: UUID, includingDeleted: Bool) -> [ProgramDay] {
        programDays.values
            .filter { $0.programID == programID }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.order, $0.id.uuidString) }
    }

    /// One day, subject to rule 1.
    func programDay(id: UUID, includingDeleted: Bool) -> ProgramDay? {
        programDays[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// Inserts or replaces a day.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when the program or the routine names no row.
    func saveProgramDay(_ day: ProgramDay) throws {
        try requireReferenced(programs, id: day.programID, from: day.id)
        try requireReferenced(routines, id: day.routineID, from: day.id)
        upserted(day, into: &programDays, at: .now)
    }

    /// Soft-deletes one day.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live day
    ///   carries `id`.
    func deleteProgramDay(id: UUID) throws {
        try softDelete(id: id, in: &programDays, at: .now)
    }

    /// The open run with the latest start, resolved the way the real repository resolves it.
    func currentProgramRun() -> ProgramRun? {
        programRuns.values
            .filter { $0.isOpen }
            .max {
                ($0.startedAt, $0.updatedAt, $0.id.uuidString)
                    < ($1.startedAt, $1.updatedAt, $1.id.uuidString)
            }
    }

    /// Every pass through the program, newest start first.
    func programRuns(forProgramID programID: UUID, includingDeleted: Bool) -> [ProgramRun] {
        programRuns.values
            .filter { $0.programID == programID }
            .live(includingDeleted: includingDeleted)
            .sorted {
                ($0.startedAt, $0.updatedAt, $0.id.uuidString)
                    > ($1.startedAt, $1.updatedAt, $1.id.uuidString)
            }
    }

    /// One run, subject to rule 1.
    func programRun(id: UUID, includingDeleted: Bool) -> ProgramRun? {
        programRuns[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// Opens `run` and closes every other open run at its start (`FR-16.8.4`).
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when the program names no row.
    func startProgramRun(_ run: ProgramRun) throws {
        try requireReferenced(programs, id: run.programID, from: run.id)

        let now = Date.now
        for other in programRuns.values where other.isOpen && other.id != run.id {
            programRuns[other.id] = ProgramRun(
                id: other.id,
                createdAt: other.createdAt,
                updatedAt: now,
                deletedAt: other.deletedAt,
                programID: other.programID,
                startedAt: other.startedAt,
                endedAt: run.startedAt,
                weekNumber: other.weekNumber,
                nextDayIndex: other.nextDayIndex)
        }
        upserted(run, into: &programRuns, at: now)
    }

    /// Inserts or replaces a run, touching no other row.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when the program names no row.
    func saveProgramRun(_ run: ProgramRun) throws {
        try requireReferenced(programs, id: run.programID, from: run.id)
        upserted(run, into: &programRuns, at: .now)
    }

    /// Soft-deletes one run.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live run
    ///   carries `id`.
    func deleteProgramRun(id: UUID) throws {
        try softDelete(id: id, in: &programRuns, at: .now)
    }
}
