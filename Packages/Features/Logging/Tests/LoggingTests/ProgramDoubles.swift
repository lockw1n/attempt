import Foundation
import RepositoryInterface

/// A program store whose every read refuses, for the week's and the day's failed-read states.
///
/// **A file of its own rather than a suite's**, because the suite that used to declare it is gone
/// and the two that use it now are `WeekStateTests` and `DayStoreTests`.
struct UnreadablePrograms: ProgramRepository {
    /// What every call raises.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    func programs(includingDeleted: Bool) async throws -> [Program] { throw failure }
    func program(id: UUID, includingDeleted: Bool) async throws -> Program? { throw failure }
    func save(_ program: Program) async throws { throw failure }
    func deleteProgram(id: UUID) async throws { throw failure }
    func days(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramDay] {
        throw failure
    }
    func programDay(id: UUID, includingDeleted: Bool) async throws -> ProgramDay? { throw failure }
    func save(_ day: ProgramDay) async throws { throw failure }
    func deleteDay(id: UUID) async throws { throw failure }
    func currentRun() async throws -> ProgramRun? { throw failure }
    func runs(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramRun] {
        throw failure
    }
    func run(id: UUID, includingDeleted: Bool) async throws -> ProgramRun? { throw failure }
    func startRun(_ run: ProgramRun) async throws { throw failure }
    func save(_ run: ProgramRun) async throws { throw failure }
    func deleteRun(id: UUID) async throws { throw failure }
}
