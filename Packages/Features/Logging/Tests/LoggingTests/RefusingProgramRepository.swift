import Foundation
import RepositoryInterface

/// A program store that passes through to another and refuses one nominated write.
///
/// **A decorator rather than a stub**, on `SlotRefusingRoutineRepository`'s argument one screen
/// over: the interesting failures here are *partial* — some rows land and one does not — and a
/// store that refused everything could not produce one. Both switches are addressed by identity
/// rather than by a call count, so a test says which write fails instead of counting the writes
/// before it.
struct RefusingProgramRepository: ProgramRepository {
    /// What the refused write throws.
    struct Refusal: Error {}

    /// The store every other call reaches.
    let wrapped: any ProgramRepository

    /// The day whose ``ProgramRepository/save(_:)-(ProgramDay)`` throws, or `nil`.
    var refusedDayID: UUID?

    /// Whether ``ProgramRepository/save(_:)-(ProgramRun)`` throws — the cursor write.
    var refusesRunSave = false

    func programs(includingDeleted: Bool) async throws -> [Program] {
        try await wrapped.programs(includingDeleted: includingDeleted)
    }

    func program(id: UUID, includingDeleted: Bool) async throws -> Program? {
        try await wrapped.program(id: id, includingDeleted: includingDeleted)
    }

    func save(_ program: Program) async throws { try await wrapped.save(program) }

    func deleteProgram(id: UUID) async throws { try await wrapped.deleteProgram(id: id) }

    func days(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramDay] {
        try await wrapped.days(forProgramID: programID, includingDeleted: includingDeleted)
    }

    func programDay(id: UUID, includingDeleted: Bool) async throws -> ProgramDay? {
        try await wrapped.programDay(id: id, includingDeleted: includingDeleted)
    }

    func save(_ day: ProgramDay) async throws {
        guard day.id != refusedDayID else { throw Refusal() }
        try await wrapped.save(day)
    }

    func deleteDay(id: UUID) async throws { try await wrapped.deleteDay(id: id) }

    func currentRun() async throws -> ProgramRun? { try await wrapped.currentRun() }

    func runs(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramRun] {
        try await wrapped.runs(forProgramID: programID, includingDeleted: includingDeleted)
    }

    func run(id: UUID, includingDeleted: Bool) async throws -> ProgramRun? {
        try await wrapped.run(id: id, includingDeleted: includingDeleted)
    }

    func startRun(_ run: ProgramRun) async throws { try await wrapped.startRun(run) }

    func save(_ run: ProgramRun) async throws {
        guard !refusesRunSave else { throw Refusal() }
        try await wrapped.save(run)
    }

    func deleteRun(id: UUID) async throws { try await wrapped.deleteRun(id: id) }
}
