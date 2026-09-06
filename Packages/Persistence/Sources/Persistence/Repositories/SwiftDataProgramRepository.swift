import Foundation
import RepositoryInterface
import SwiftData

/// `ProgramRepository` over SwiftData (`TR-0.4.2`, `TR-16.2`, `FR-16.8`).
///
/// Three levels joined by `UUID` columns, because `G-2.5` forbids relationships — so the cascade is
/// written here rather than inherited from the store, the same shape ``SwiftDataRoutineRepository``
/// uses.
@ModelActor
actor SwiftDataProgramRepository: ProgramRepository {
    func programs(includingDeleted: Bool) throws -> [Program] {
        try modelContext.rows(ProgramEntity.self, includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.name, $0.id.uuidString) }
            .map(\.record)
    }

    func program(id: UUID, includingDeleted: Bool) throws -> Program? {
        try modelContext.row(ProgramEntity.self, id: id, includingDeleted: includingDeleted)?.record
    }

    func save(_ program: Program) throws {
        try modelContext.upsert(program, as: ProgramEntity.self)
        try modelContext.saveStamped()
    }

    /// Soft-deletes the program, its days and its runs, in one write.
    ///
    /// **Every row carrying `id` is swept, not just the one a read would return** — see
    /// ``SwiftDataWorkoutRepository/deleteSession(id:)`` for why. The runs go with the days because
    /// a run through a deleted program is one ``currentRun()`` would still hand back.
    func deleteProgram(id: UUID) throws {
        let programs = try modelContext.rows(ProgramEntity.self, id: id, includingDeleted: false)
        guard !programs.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for program in programs { program.markDeleted(at: now) }

        let days = try modelContext.rows(
            ProgramDayEntity.self,
            matching: #Predicate { $0.programID == id },
            includingDeleted: false
        )
        for day in days { day.markDeleted(at: now) }

        let runs = try modelContext.rows(
            ProgramRunEntity.self,
            matching: #Predicate { $0.programID == id },
            includingDeleted: false
        )
        for run in runs { run.markDeleted(at: now) }
        try modelContext.saveStamped(at: now)
    }

    /// The program's days in ``ProgramDay/order``, whatever their routines have become — see the
    /// protocol for why an archived routine is not this read's refusal to make.
    func days(forProgramID programID: UUID, includingDeleted: Bool) throws -> [ProgramDay] {
        try modelContext.rows(
            ProgramDayEntity.self,
            matching: #Predicate { $0.programID == programID },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically { ($0.order, $0.id.uuidString) }
        .map(\.record)
    }

    func programDay(id: UUID, includingDeleted: Bool) throws -> ProgramDay? {
        try modelContext.row(ProgramDayEntity.self, id: id, includingDeleted: includingDeleted)?
            .record
    }

    func save(_ day: ProgramDay) throws {
        try modelContext.requireReferenced(ProgramEntity.self, id: day.programID, from: day.id)
        try modelContext.requireReferenced(RoutineEntity.self, id: day.routineID, from: day.id)
        try modelContext.upsert(day, as: ProgramDayEntity.self)
        try modelContext.saveStamped()
    }

    func deleteDay(id: UUID) throws {
        let days = try modelContext.rows(ProgramDayEntity.self, id: id, includingDeleted: false)
        guard !days.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for day in days { day.markDeleted(at: now) }
        try modelContext.saveStamped(at: now)
    }

    /// The open run, by the latest ``ProgramRun/startedAt`` and then rule 2's own order.
    ///
    /// The pick is a tie-break rather than a policy — ``startRun(_:)`` is what keeps the match set
    /// down to one — so it answers a merged or restored store rather than a normal one.
    func currentRun() throws -> ProgramRun? {
        let open = try modelContext.rows(
            ProgramRunEntity.self,
            matching: #Predicate { $0.endedAt == nil },
            includingDeleted: false
        )
        return open.max {
            ($0.startedAt, $0.updatedAt, $0.id.uuidString)
                < ($1.startedAt, $1.updatedAt, $1.id.uuidString)
        }?.record
    }

    func runs(forProgramID programID: UUID, includingDeleted: Bool) throws -> [ProgramRun] {
        try modelContext.rows(
            ProgramRunEntity.self,
            matching: #Predicate { $0.programID == programID },
            includingDeleted: includingDeleted
        )
        // The key `currentRun()` maximises, reversed — so the run in force is the one on top even
        // where two share a start date, which is what a restored file can produce.
        .sorted {
            ($0.startedAt, $0.updatedAt, $0.id.uuidString)
                > ($1.startedAt, $1.updatedAt, $1.id.uuidString)
        }
        .map(\.record)
    }

    func run(id: UUID, includingDeleted: Bool) throws -> ProgramRun? {
        try modelContext.row(ProgramRunEntity.self, id: id, includingDeleted: includingDeleted)?
            .record
    }

    /// Closes every other open run at `run`'s start, then writes `run`.
    ///
    /// **The predicate is what keeps the loop from restamping a row that did not move**, and it is
    /// doing the work the "did this change?" clause does elsewhere: assigning a `@Model` property
    /// marks the row dirty whatever the value was, and `saveStamped` then moves `updatedAt` —
    /// `G-2.4`'s conflict key — so a no-op write here would outrank a real remote edit. Matching
    /// only `endedAt == nil` means every row the loop touches genuinely changes, which is why there
    /// is no such clause in the body. Widen the predicate and the clause has to come back.
    func startRun(_ run: ProgramRun) throws {
        try modelContext.requireReferenced(ProgramEntity.self, id: run.programID, from: run.id)

        let identifier = run.id
        let open = try modelContext.rows(
            ProgramRunEntity.self,
            matching: #Predicate { $0.endedAt == nil && $0.id != identifier },
            includingDeleted: false
        )
        let now = Date.now
        for other in open { other.endedAt = run.startedAt }
        try modelContext.upsert(run, as: ProgramRunEntity.self)
        try modelContext.saveStamped(at: now)
    }

    func save(_ run: ProgramRun) throws {
        try modelContext.requireReferenced(ProgramEntity.self, id: run.programID, from: run.id)
        try modelContext.upsert(run, as: ProgramRunEntity.self)
        try modelContext.saveStamped()
    }

    func deleteRun(id: UUID) throws {
        let runs = try modelContext.rows(ProgramRunEntity.self, id: id, includingDeleted: false)
        guard !runs.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for run in runs { run.markDeleted(at: now) }
        try modelContext.saveStamped(at: now)
    }
}
