import Foundation
import RepositoryInterface

/// One day of the program, as the editor draws it (`FR-16.8.1`).
public struct ProgramDayRow: Identifiable, Equatable, Sendable {
    /// The day's own identifier.
    public let id: UUID

    /// The routine trained on it.
    public let routineID: UUID

    /// That routine's name, or `nil` where it has been archived (`FR-15.2.5`).
    ///
    /// **`nil` rather than a stand-in sentence**, because the difference is the screen's to draw:
    /// an archived routine is a day the lifter has to repoint or drop, and a name it does not have
    /// is not copy this type can write.
    public let routineName: String?
}

/// A routine the editor offers as a day (`FR-16.8.1`).
public struct ProgramRoutineChoice: Identifiable, Equatable, Sendable {
    /// The routine's identifier.
    public let id: UUID

    /// Its name.
    public let name: String
}

/// The editor over one program: its name, its note, and the days it is made of (`FR-16.8.1`).
///
/// **Screen-lifetime, unlike ``RoutineEditorState``**, and the difference is where a day comes
/// from: a routine's exercises are chosen on a screen pushed *over* the editor, so its draft has to
/// outlive the push, where a program's days are picked from a list on this screen.
///
/// **The name and the note are a draft; the days are written straight through.** Text is typed and
/// a half-typed name is not a fact about the program until **Save** — the routine editor's own
/// rule. A day is a routine picked from a list, which is a choice rather than an edit, and holding
/// those in a draft would mean a lifter who added three days and left had added none.
@Observable
public final class ProgramEditorState {
    /// What the screen has to show, as one value rather than four flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet.
        case idle

        /// A read is in flight.
        case loading

        /// The program, its days and the routines it can be built from.
        case ready

        /// No live program carries the identifier the route named.
        case missing

        /// The read failed, carrying the error's description — a diagnostic, not copy (`G-3.4`).
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// What is in the name field. The lifter's, and one of the two properties they move.
    public var name = ""

    /// What is in the note field. See ``name``.
    public var notes = ""

    /// The program's days, in ``RepositoryInterface/ProgramDay/order``.
    public private(set) var days: [ProgramDayRow] = []

    /// Every live routine, as a day this program could have.
    public private(set) var choices: [ProgramRoutineChoice] = []

    /// Whether this is the program in force (`FR-16.8.1`).
    public private(set) var isCurrent = false

    /// Whether the last write changed nothing because the store refused.
    ///
    /// **One flag rather than ``ProgramManagementFailure``**, because every write on this screen
    /// fails the same way: the name is the only typed field and it is allowed to be empty here —
    /// see ``saveDetails()``.
    public private(set) var writeFailed = false

    /// What the record said when it was last read — what ``hasUnsavedDetails`` compares against.
    private var stored: (name: String, notes: String) = ("", "")

    /// Whether the name or the note differs from the record.
    public var hasUnsavedDetails: Bool { name != stored.name || notes != stored.notes }

    /// The program being edited.
    private let programID: UUID

    /// The programs, their days and the run in force.
    private let repository: any ProgramRepository

    /// The routines a day can name.
    private let routines: any RoutineRepository

    /// Builds the editor over one program.
    ///
    /// - Parameters:
    ///   - programID: The program the route named.
    ///   - repository: Where programs, days and runs come from.
    ///   - routines: Where the days' routines come from.
    public init(
        programID: UUID, repository: any ProgramRepository, routines: any RoutineRepository
    ) {
        self.programID = programID
        self.repository = repository
        self.routines = routines
    }

    /// Reads the program, its days and the routines it can be built from.
    ///
    /// **An unsaved name or note survives a re-read**, on `SessionNoteDraft.follow(_:)`'s
    /// rule: every write on this screen re-reads, and a read that overwrote the field would drop
    /// whatever had been typed since.
    public func load() async {
        if phase == .loading { return }
        phase = .loading
        writeFailed = false
        do {
            guard let program = try await repository.program(id: programID, includingDeleted: false)
            else {
                phase = .missing
                return
            }
            let hadUnsavedDetails = hasUnsavedDetails
            stored = (program.name, program.notes)
            if !hadUnsavedDetails {
                name = program.name
                notes = program.notes
            }
            days = try await read(
                try await repository.days(forProgramID: programID, includingDeleted: false))
            choices = try await routines.routines(includingDeleted: false)
                .map { ProgramRoutineChoice(id: $0.id, name: $0.name) }
            isCurrent = try await repository.currentRun()?.programID == programID
            phase = .ready
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Resolves each day's routine name, `nil` where it has been archived.
    ///
    /// - Parameter days: The program's days, in order.
    /// - Returns: The rows.
    /// - Throws: Whatever the routine repository throws.
    private func read(_ days: [ProgramDay]) async throws -> [ProgramDayRow] {
        var rows: [ProgramDayRow] = []
        for day in days {
            rows.append(
                ProgramDayRow(
                    id: day.id,
                    routineID: day.routineID,
                    routineName: try await routines.routine(
                        id: day.routineID, includingDeleted: false)?.name))
        }
        return rows
    }

    /// Stores the name and the note (`FR-16.8.1`).
    ///
    /// **An empty name is stored rather than refused**, which is where this parts company with the
    /// routine editor. A routine's name is the only thing a list row has to identify it by; a
    /// program's row also carries its day count, and the list draws the same stand-in a routine
    /// with no name gets. Refusing here would leave a lifter unable to clear a typo without
    /// inventing a name first.
    public func saveDetails() async {
        do {
            guard let program = try await repository.program(id: programID, includingDeleted: false)
            else {
                phase = .missing
                return
            }
            // Rebuilt whole because `Program` is immutable, and every column but the two typed
            // fields is the original's; the upsert restamps `updatedAt` regardless.
            try await repository.save(
                Program(
                    id: program.id,
                    createdAt: program.createdAt,
                    updatedAt: program.updatedAt,
                    deletedAt: program.deletedAt,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: notes))
        } catch {
            writeFailed = true
            return
        }
        await load()
    }

    /// Appends a day naming `routineID` (`FR-16.8.1`).
    ///
    /// **The new day's order is one past the last**, not the count: orders are what
    /// ``RepositoryInterface/ProgramRun/nextDayIndex`` is a cursor into, and reusing an order a
    /// soft-deleted day still holds would put two days in one place.
    ///
    /// - Parameter routineID: The routine to train on it.
    public func addDay(routineID: UUID) async {
        let now = Date.now
        do {
            let stored = try await repository.days(forProgramID: programID, includingDeleted: true)
            try await repository.save(
                ProgramDay(
                    id: UUID(),
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    programID: programID,
                    routineID: routineID,
                    order: (stored.map(\.order).max() ?? -1) + 1))
        } catch {
            writeFailed = true
            return
        }
        await load()
    }

    /// Takes one day out of the program.
    ///
    /// **Soft, like every deletion here** (`G-1.3`), and nothing cascades: a routine outlives the
    /// days naming it.
    ///
    /// - Parameter dayID: The day to remove.
    public func removeDay(id dayID: UUID) async {
        do {
            try await repository.deleteDay(id: dayID)
        } catch RepositoryError.recordNotFound {
            await load()
            return
        } catch {
            writeFailed = true
            return
        }
        // Dropped here rather than left to the read: ``renumber()`` walks this list, and a row that
        // is gone from the store but still in it would leave a hole in the orders it writes.
        days.removeAll { $0.id == dayID }
        await renumber()
    }

    /// Moves one day up or down the week.
    ///
    /// - Parameters:
    ///   - index: Its current position in ``days``.
    ///   - offset: `-1` for earlier, `1` for later.
    public func moveDay(at index: Int, by offset: Int) async {
        let target = index + offset
        guard days.indices.contains(index), days.indices.contains(target) else { return }
        days.swapAt(index, target)
        await renumber()
    }

    /// Writes ``days``' current sequence back as orders `0…n-1`.
    ///
    /// **Every day is rewritten, not only the pair that moved**, because a removal renumbers the
    /// tail as well — and the orders have to stay dense for
    /// ``RepositoryInterface/ProgramRun/nextDayIndex`` to mean "the day after this one".
    private func renumber() async {
        do {
            let stored = try await repository.days(forProgramID: programID, includingDeleted: false)
            let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
            // Only the rows the store still holds, and in ``days``' order: a day removed under this
            // screen must not be counted a position, or every day after it keeps the order it had.
            for (position, day) in days.compactMap({ byID[$0.id] }).enumerated() {
                guard day.order != position else { continue }
                try await repository.save(day.reordered(to: position))
            }
        } catch {
            writeFailed = true
            return
        }
        await load()
    }

    /// Makes this the program in force (`FR-16.8.1`, `FR-16.8.2`).
    ///
    /// **The last pass through this program is reopened where there is one**, rather than a fresh
    /// week 1 every time: a lifter who ran another program for a fortnight and came back is in the
    /// week they left, and `FR-16.8.4` is the only thing that advances one.
    ///
    /// **``RepositoryInterface/ProgramRepository/startRun(_:)``, not `save`** — closing every other
    /// open run is the invariant `FR-16.8.1` needs and the only place it lives.
    public func makeCurrent() async {
        do {
            let previous = try await repository.runs(forProgramID: programID, includingDeleted: false)
                .first
            let now = Date.now
            try await repository.startRun(
                previous?.reopened(at: now)
                    ?? ProgramRun(
                        id: UUID(),
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil,
                        programID: programID,
                        startedAt: now,
                        endedAt: nil,
                        weekNumber: 1,
                        nextDayIndex: 0))
        } catch {
            writeFailed = true
            return
        }
        await load()
    }
}

extension ProgramDay {
    /// This day at another position, every other column untouched.
    ///
    /// - Parameter order: Its new position in the week.
    /// - Returns: The record to store.
    func reordered(to order: Int) -> ProgramDay {
        ProgramDay(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            programID: programID,
            routineID: routineID,
            order: order)
    }
}

extension ProgramRun {
    /// This run open again, its week and its cursor where they were left.
    ///
    /// **``startedAt`` moves and the week does not.** The pass is being resumed rather than
    /// restarted, so what changes is when it became current — which is what orders the passes and
    /// what every other open run is closed at.
    ///
    /// - Parameter moment: When it became current again.
    /// - Returns: The record to store.
    func reopened(at moment: Date) -> ProgramRun {
        ProgramRun(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            programID: programID,
            startedAt: moment,
            endedAt: nil,
            weekNumber: weekNumber,
            nextDayIndex: nextDayIndex)
    }
}
