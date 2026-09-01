import Foundation
import RepositoryInterface

/// One routine as the list draws it (`FR-15.2.1`).
public struct RoutineSummary: Identifiable, Equatable, Sendable {
    /// The routine's identifier, which is what the row's route carries.
    public let id: UUID

    /// The routine's name, as the lifter titled it.
    public let name: String

    /// How many exercises it prescribes — the one fact a row adds to the name.
    ///
    /// **Exercises rather than sets**, because a routine's length is what a lifter picks between:
    /// the set count is inside the plan and is what the editor is for.
    public let exerciseCount: Int
}

/// The routine list, as state rather than as a view model (`TR-1.2`, `FR-15.2.1`).
///
/// **Screen-lifetime, unlike ``RoutineEditorState``**: nothing outlives this screen, and `TR-1.2`
/// allows a store exactly where something does.
@Observable
public final class RoutineListState {
    /// What the screen has to show, as one value rather than three flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet.
        case idle

        /// A read is in flight.
        case loading

        /// The routines, which may be none.
        case ready

        /// The read failed, carrying the error's description — a diagnostic, not copy (`G-3.4`).
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The routines, by name then id — the repository's own order, which is the one read in this
    /// module sorted on a name rather than on a position.
    public private(set) var routines: [RoutineSummary] = []

    /// Whether the last attempt to start a workout from a routine did not start one
    /// (`FR-15.2.3`).
    ///
    /// **A screen fact rather than a store one**, on `LastWorkoutState`'s precedent for the same
    /// command: starting the workout is `Logging`'s and happens behind a closure, so what this
    /// screen knows is whether the one it asked for happened. Cleared by the next attempt, and by
    /// every fresh read — a read that succeeds retires a claim about a write that failed.
    public private(set) var startDidFail = false

    private let repository: any RoutineRepository

    /// Builds the list over the repository it reads through.
    public init(repository: any RoutineRepository) {
        self.repository = repository
    }

    /// Reads the routines, on every appearance and on every retry.
    ///
    /// **Re-entrant through ``Phase/ready``, unlike the editor's read**: this screen holds nothing
    /// the user typed, and a routine saved on the screen pushed over it has to appear on the way
    /// back.
    public func load() async {
        if phase == .loading { return }
        phase = .loading
        startDidFail = false
        do {
            let stored = try await repository.routines(includingDeleted: false)
            var summaries: [RoutineSummary] = []
            for routine in stored {
                // One read per routine, the repository declaring no relationships (`G-2.5`). The
                // count is the row's only derived fact and there is no cheaper way to it.
                let slots = try await repository.exercises(
                    forRoutineID: routine.id, includingDeleted: false)
                summaries.append(
                    RoutineSummary(
                        id: routine.id, name: routine.name, exerciseCount: slots.count))
            }
            routines = summaries
            phase = .ready
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Records what starting a workout from a routine did (`FR-15.2.3`).
    ///
    /// **A workout that did not start is the only outcome worth reporting**, and the reason it can
    /// happen is one the lifter can act on: there is one workout in progress by construction, so a
    /// routine started on top of an unfinished session is refused rather than queued.
    ///
    /// - Parameter started: Whether a workout is now in progress.
    public func startDidFinish(started: Bool) {
        startDidFail = !started
    }
}
