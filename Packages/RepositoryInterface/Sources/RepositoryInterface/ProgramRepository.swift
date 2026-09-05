import Foundation

/// Programs, the days within them, and the runs through them (`TR-16.2`, `FR-16.8`).
///
/// Three levels rather than one nested tree, for ``RoutineRepository``'s reason: the schema declares
/// no relationships (`G-2.5`) and a repository that returned a tree would be inventing one. What it
/// does own is the **order** of a program's days and the invariant that at most one run is open.
public protocol ProgramRepository: Sendable {
    /// Every program (`FR-16.8.1`), by name then id.
    func programs(includingDeleted: Bool) async throws -> [Program]

    /// One program, or `nil` if no row carries that id.
    func program(id: UUID, includingDeleted: Bool) async throws -> Program?

    /// Inserts or replaces the program, keyed on ``Program/id``.
    func save(_ program: Program) async throws

    /// Soft-deletes the program and, with it, its days and its runs.
    ///
    /// The cascade is rule 3's, and the runs are in it for the same reason the days are: a run
    /// through a program the lifter deleted is a run ``currentRun()`` would otherwise still hand
    /// back, with nothing behind it to train.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live program carries that id.
    func deleteProgram(id: UUID) async throws

    /// The days in one program, in ``ProgramDay/order``.
    ///
    /// **A day whose routine has been archived is returned like any other, and the row is intact.**
    /// `FR-15.2.5`'s archive is a soft delete and nothing sweeps the days naming it, so this read
    /// cannot promise every ``ProgramDay/routineID`` resolves to a live routine — it promises the
    /// days, and the caller resolving one is where a missing routine is answered. Refusing here
    /// would cost the lifter the whole program for one archived routine, which is rule 4's
    /// direction: the dangling half costs that day, never the program.
    func days(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramDay]

    /// One day, or `nil` if no row carries that id.
    func programDay(id: UUID, includingDeleted: Bool) async throws -> ProgramDay?

    /// Inserts or replaces the day, keyed on ``ProgramDay/id``.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the program or the
    ///   routine does not exist.
    func save(_ day: ProgramDay) async throws

    /// Soft-deletes one day. Nothing cascades from here — a routine outlives the days naming it.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live day carries that id.
    func deleteDay(id: UUID) async throws

    /// The run in force — the open run, or `nil` where the lifter is running nothing.
    ///
    /// **No `includingDeleted:`, and it is not an omission** — rule 1's second paragraph in this
    /// module's header. This resolves to the run in force, and a soft-deleted run is one whose
    /// program the lifter deleted.
    ///
    /// **At most one run is open at a time and ``startRun(_:)`` is what holds that**, so the
    /// resolution here is a tie-break rather than a policy: a store that somehow holds two open runs
    /// — a merge, a restored file — answers with the later ``ProgramRun/startedAt``, then rule 2's
    /// own order. `FR-16.8.1`'s "one may be current" is the whole of what this returns.
    func currentRun() async throws -> ProgramRun?

    /// Every pass through one program, newest ``ProgramRun/startedAt`` first.
    ///
    /// The history-shaped sibling of ``currentRun()``, and it takes the flag for that reason.
    func runs(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramRun]

    /// One run, or `nil` if no row carries that id.
    func run(id: UUID, includingDeleted: Bool) async throws -> ProgramRun?

    /// Opens `run` and closes every other open run, in one write (`FR-16.8.4`).
    ///
    /// **The closing is the point, and it is here rather than left to a caller** for the reason
    /// ``EquipmentRepository/makeDefault(profileID:)`` exists: "at most one open run" is a
    /// cross-row invariant that no single row's write can hold, so an upsert alone cannot hold it
    /// either. Every other open run is closed at `run`'s own ``ProgramRun/startedAt``, so the
    /// passes abut rather than overlap.
    ///
    /// **Across programs, not only within one.** `FR-16.8.1` says one program may be current and
    /// `FR-16.8.2` draws *the* current program's next day, so two programs both open would leave
    /// that screen without an answer.
    ///
    /// **A run already stored is reopened rather than duplicated**, keyed on ``ProgramRun/id`` —
    /// and it does not close itself.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the program does
    ///   not exist.
    func startRun(_ run: ProgramRun) async throws

    /// Inserts or replaces the run, keyed on ``ProgramRun/id``, and touches no other row.
    ///
    /// **It does not hold ``startRun(_:)``'s invariant**, deliberately: this is how a run in
    /// progress advances its week and its day cursor, and how one is closed by writing
    /// ``ProgramRun/endedAt``. A save that also closed the other runs would close them again on
    /// every advance, restamping rows nothing changed — and `updatedAt` is `G-2.4`'s conflict key.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the program does
    ///   not exist.
    func save(_ run: ProgramRun) async throws

    /// Soft-deletes one run.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live run carries that id.
    func deleteRun(id: UUID) async throws
}
