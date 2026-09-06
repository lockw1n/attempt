import Foundation
import RepositoryInterface

/// One program as the list draws it (`FR-16.8.1`).
public struct ProgramSummary: Identifiable, Equatable, Sendable {
    /// The program's identifier, which is what the row's route carries.
    public let id: UUID

    /// The program's name, as the lifter titled it.
    public let name: String

    /// How many days it is made of — the one fact a row adds to the name, on
    /// ``RoutineSummary/exerciseCount``'s argument.
    public let dayCount: Int

    /// Whether this is the program in force (`FR-16.8.1`'s "one may be current").
    public let isCurrent: Bool
}

/// Why a program was not written (`FR-16.8.1`).
///
/// The same two answers ``RoutineManagementFailure`` has, for its reason: an empty name names
/// something the lifter can fix in the field they just emptied, a refused write names only the
/// store.
public enum ProgramManagementFailure: Sendable, Equatable {
    /// Nothing was written: the prompt's field held no name.
    case nameRequired

    /// Nothing was written: the store refused.
    case writeFailed
}

/// The program list, as state rather than as a view model (`TR-1.2`, `FR-16.8.1`).
///
/// **Screen-lifetime, like ``RoutineListState``**, and for its reason: nothing here outlives the
/// screen.
@Observable
public final class ProgramListState {
    /// What the screen has to show, as one value rather than three flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet.
        case idle

        /// A read is in flight.
        case loading

        /// The programs, which may be none.
        case ready

        /// The read failed, carrying the error's description — a diagnostic, not copy (`G-3.4`).
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The programs, by name then id — the repository's own order.
    public private(set) var programs: [ProgramSummary] = []

    /// Why the last **New program** wrote nothing, or `nil`.
    ///
    /// Cleared by every fresh read, on ``RoutineListState/managementFailure``'s rule.
    public private(set) var commandFailure: ProgramManagementFailure?

    /// The programs, their days and the run in force.
    private let repository: any ProgramRepository

    /// Builds the list over the repository it reads through.
    ///
    /// - Parameter repository: Where programs come from.
    public init(repository: any ProgramRepository) {
        self.repository = repository
    }

    /// Reads the programs and which one is in force, on every appearance and on every retry.
    ///
    /// **Re-entrant through ``Phase/ready``**, on ``RoutineListState/load()``'s rule: the editor
    /// pushed over this screen is what changes what it lists, and **Make current** is there.
    public func load() async {
        if phase == .loading { return }
        phase = .loading
        commandFailure = nil
        do {
            let currentProgramID = try await repository.currentRun()?.programID
            var summaries: [ProgramSummary] = []
            for program in try await repository.programs(includingDeleted: false) {
                // One read per program, the repository declaring no relationships (`G-2.5`).
                let days = try await repository.days(
                    forProgramID: program.id, includingDeleted: false)
                summaries.append(
                    ProgramSummary(
                        id: program.id,
                        name: program.name,
                        dayCount: days.count,
                        isCurrent: program.id == currentProgramID))
            }
            programs = summaries
            phase = .ready
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Writes a program under the name the prompt held (`FR-16.8.1`).
    ///
    /// **The row is written here rather than drafted in the editor**, which is what buys this
    /// feature one route instead of two — see ``AppNavigation/RoutinesRoute/programEdit(programID:)``.
    /// A program is a name and then a list of days, and the days are picked rather than typed, so
    /// there is nothing to lose by writing the name at once.
    ///
    /// **Trimmed, and an empty name is refused** — the routine editor's rule at the third place a
    /// name is typed.
    ///
    /// - Parameter name: What the lifter typed.
    /// - Returns: The new program's identifier, or `nil` where nothing was written.
    public func create(named name: String) async -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            commandFailure = .nameRequired
            return nil
        }
        let now = Date.now
        let programID = UUID()
        do {
            try await repository.save(
                Program(
                    id: programID,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    name: trimmed,
                    notes: ""))
        } catch {
            commandFailure = .writeFailed
            return nil
        }
        await load()
        return programID
    }
}
