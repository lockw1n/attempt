import Foundation
import Observation
import PowerliftingCore
import RepositoryInterface

/// What one exercise's records look like to a screen, kept current without polling (`TR-1.5`,
/// `TR-1.2`).
///
/// **The only writer of the derived value on the UI side** (`G-1.4` one level up). The actor
/// computes and this holds the latest answer, so a screen that needs the same number reads this
/// rather than asking the actor again — two readers of one store cannot disagree, two callers of one
/// actor can.
///
/// **The two halves are loaded separately because they cost differently.** ``loadRecords()`` is
/// answered from `TR-0.3.9`'s cache whenever it is current and is what a PR list wants;
/// ``loadEstimate()`` always walks the exercise's history, because an estimate depends on a setting
/// no cache can carry. A screen showing only one of them should load only that one — ``load()`` is
/// for a screen showing both.
///
/// **``observeChanges()`` is what makes it a subscription rather than a snapshot.** It runs until
/// cancelled, so it belongs in a `.task` on the screen; a change to *this* exercise reloads both
/// halves, and a settings change reloads the estimate alone — a rep max reads no setting, so nothing
/// a picker does can move one.
@MainActor
@Observable
public final class ExerciseRecordsState {
    /// The N-rep maxes, ascending by reps. Empty before anything has loaded and when the exercise
    /// holds none — ``hasLoaded`` is what separates those.
    public private(set) var repMaxes: [DatedRepMax] = []

    /// The best estimated one-rep maximum, or `nil` when no set yielded one.
    public private(set) var estimatedMax: DatedRecord?

    /// Whether ``loadRecords()`` has ever completed. An exercise with no records and one nothing has
    /// looked at are both an empty ``repMaxes``, and a screen says opposite things about them.
    public private(set) var hasLoaded = false

    /// The last read that failed, as the error's description, or `nil`. A **diagnostic**, not copy
    /// (`G-3.4`).
    public private(set) var failure: String?

    /// The exercise this is about.
    @ObservationIgnored public let exerciseID: UUID

    /// Where the numbers come from.
    @ObservationIgnored private let recomputer: PersonalRecordRecomputer

    /// The read a publish belongs to.
    ///
    /// A repository read already in flight does not notice that a newer one has started, so
    /// cancelling the task is not enough on its own: the abandoned read resumes and assigns. Every
    /// publish below is gated on this instead — the same rule the history search's walk carries.
    @ObservationIgnored private var read = 0

    /// Builds the state over the exercise it reports on.
    ///
    /// - Parameters:
    ///   - exerciseID: The exercise.
    ///   - recomputer: The app's one recomputer — shared, so that a change published by a write
    ///     anywhere reaches every screen showing the number it moved.
    public init(exerciseID: UUID, recomputer: PersonalRecordRecomputer) {
        self.exerciseID = exerciseID
        self.recomputer = recomputer
    }

    /// Reloads both halves.
    public func load() async {
        await loadRecords()
        await loadEstimate()
    }

    /// Reloads the N-rep maxes (`FR-1.6.1`).
    ///
    /// Costs no walk when the cache is current, which is the whole of what `G-1.5`'s version buys.
    public func loadRecords() async {
        let token = beginRead()
        do {
            let loaded = try await recomputer.repMaxes(forExerciseID: exerciseID)
            guard isCurrent(token) else { return }
            repMaxes = loaded
            hasLoaded = true
            failure = nil
        } catch {
            guard isCurrent(token) else { return }
            hasLoaded = true
            failure = String(describing: error)
        }
    }

    /// Reloads the estimated one-rep maximum (`FR-1.7.1`).
    ///
    /// **A failure here leaves the previous estimate on screen and does not clear ``failure``'s
    /// counterpart**: the estimate is one number beside a list, and blanking the list because the
    /// tile could not be refreshed reports the wrong thing failed.
    public func loadEstimate() async {
        let token = beginRead()
        do {
            let loaded = try await recomputer.estimatedMax(forExerciseID: exerciseID)
            guard isCurrent(token) else { return }
            estimatedMax = loaded
            failure = nil
        } catch {
            guard isCurrent(token) else { return }
            failure = String(describing: error)
        }
    }

    /// Keeps this current until cancelled (`TR-1.5`).
    ///
    /// **A change to another exercise is ignored rather than reloaded**, which is `FR-1.6.4`'s scope
    /// arriving on the read side: every logged set publishes, and a screen that reloaded on all of
    /// them would walk this exercise's history because a different one was trained.
    public func observeChanges() async {
        for await change in await recomputer.changes() {
            switch change {
            case .exercise(let changed) where changed == exerciseID:
                await load()
            case .everyExercise:
                await loadEstimate()
            case .exercise:
                continue
            }
        }
    }

    /// Claims the next read's token. Taken before the first `await`.
    private func beginRead() -> Int {
        read += 1
        return read
    }

    /// Whether the read `token` belongs to is still the one the screen is waiting for.
    private func isCurrent(_ token: Int) -> Bool {
        token == read && !Task.isCancelled
    }
}
