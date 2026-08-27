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
/// **The three loads are separate because they cost differently.** ``loadRecords()`` is answered
/// from `TR-0.3.9`'s cache whenever it is current, so it is the one a badge on a logging screen can
/// afford; ``loadSources()`` and ``loadEstimate()`` each walk the exercise's history, the first
/// because a set is not readable by its own identifier and the second because an estimate depends on
/// a setting no cache can carry. A screen showing only the numbers loads only the first — ``load()``
/// is for a screen showing all of it.
///
/// **``observeChanges(includingRecords:includingEstimate:)`` is what makes it a subscription rather
/// than a snapshot.** It runs until cancelled, so it belongs in a `.task` on the screen; a change to
/// *this* exercise reloads all of it, and a settings change reloads the estimate alone — a rep max
/// reads no setting, so nothing a picker does can move one. Each half can be declined by a screen
/// that does not draw it.
@MainActor
@Observable
public final class ExerciseRecordsState {
    /// The N-rep maxes, ascending by reps. Empty before anything has loaded and when the exercise
    /// holds none — ``hasLoaded`` is what separates those.
    public private(set) var repMaxes: [DatedRepMax] = []

    /// `FR-1.7.1`'s estimate — the number, or the reason there is none. `nil` before
    /// ``loadEstimate()`` has ever answered, which is the third thing a screen says.
    public private(set) var estimate: EstimatedMax?

    /// The estimate's **computed** record alone, for a caller with no interest in why it is absent.
    /// A manual override answers `nil` — see ``DerivedValues/EstimatedMax/record``.
    public var estimatedMax: DatedRecord? { estimate?.record }

    /// The session the estimate's source set was performed in, or `nil` — `FR-1.7.4`'s link.
    ///
    /// **Resolved by ``loadEstimate()`` rather than by ``loadSources()``**, because the two answer
    /// for different halves and a screen drawing only the estimate calls only the one. Best-effort,
    /// on ``sourceSessions``' rule: a set that will not resolve is a number with no link.
    ///
    /// `nil` for a manual override, which has no source set at all, and for an absent estimate.
    public private(set) var estimateSourceSession: UUID?

    /// Why the last ``setManualEstimate(_:)`` failed, or `nil` — a **diagnostic**, not copy
    /// (`G-3.4`).
    ///
    /// Its own property rather than one of the two reads': a write that fails leaves the number on
    /// screen exactly as it was, and reporting it as a failed *read* would blank a value nothing is
    /// wrong with.
    public private(set) var manualFailure: String?

    /// The session each record's source set was performed in, keyed on the set — `FR-1.6.2`'s link.
    ///
    /// **A separate map rather than a field on ``DatedRepMax``**, because the two have the lifetimes
    /// the type's note describes: a rep max is cached and a session is a join resolved on read, so a
    /// record carrying one would be a cached copy of where a set lives (`G-1.4`).
    ///
    /// **A set missing from here is a record with no link, not a record with no session.** The
    /// resolution is best-effort — see ``PersonalRecordRecomputer/sessionIDs(forSetIDs:inExerciseID:)``
    /// — and a row simply renders without its link.
    public private(set) var sourceSessions: [UUID: UUID] = [:]

    /// Whether ``loadRecords()`` has ever completed. An exercise with no records and one nothing has
    /// looked at are both an empty ``repMaxes``, and a screen says opposite things about them.
    public private(set) var hasLoaded = false

    /// The last read that failed, as the error's description, or `nil`. A **diagnostic**, not copy
    /// (`G-3.4`).
    ///
    /// **Two reads, one report, and the records' half is the one that speaks.** The halves fail
    /// independently, so each records its own privately; one stored property shared between them let
    /// whichever finished *last* answer for both, and since ``load()`` runs the estimate second, a
    /// successful estimate cleared a failed record read's diagnostic — leaving an empty list, a
    /// `true` ``hasLoaded`` and no failure, which is precisely the "this exercise holds no records"
    /// state those two exist to keep apart (`FR-1.13.1`).
    ///
    /// **A screen drawing one half reads that half's own** — ``recordsFailure`` or
    /// ``estimateFailure`` — rather than this. Merged, a failure of the half it does not draw has it
    /// report the half it does as unreadable, which is the same confusion one shared property caused
    /// one level down. This is for a screen showing both.
    public var failure: String? { recordsFailure ?? estimateFailure }

    /// Why ``loadRecords()`` last failed, or `nil` — the list's own, and what a screen drawing only
    /// the list reads.
    public private(set) var recordsFailure: String?

    /// Why ``loadEstimate()`` last failed, or `nil` — the estimate's own, on ``recordsFailure``'s
    /// rule.
    public private(set) var estimateFailure: String?

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

    /// Reloads everything a screen showing the whole picture needs.
    ///
    /// **The link resolution is in here rather than left to the caller**, because a change that moves
    /// a record moves the set behind it: a list that reloaded its numbers and kept the old links
    /// would offer `FR-1.6.2`'s navigation to the session that *used* to hold the record. It costs one
    /// more walk of the exercise's sets, which is the walk ``loadEstimate()`` already performs
    /// unconditionally two lines below — a screen that wants only the cached numbers calls
    /// ``loadRecords()`` and pays neither.
    public func load() async {
        await loadRecords()
        await loadSources()
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
            // The links belong to the list they were resolved for. Kept across a replacement they
            // would key on sets that are no longer records, which is a link on the wrong row rather
            // than a missing one — see ``sourceSessions``.
            sourceSessions = [:]
            hasLoaded = true
            recordsFailure = nil
        } catch {
            guard isCurrent(token) else { return }
            hasLoaded = true
            recordsFailure = String(describing: error)
        }
    }

    /// Reloads where each record's source set was performed (`FR-1.6.2`).
    ///
    /// **Resolves whatever ``repMaxes`` holds now**, so it belongs after ``loadRecords()`` and not
    /// before it; called on its own it re-resolves the list already on screen, which is what a retry
    /// of a link that came back empty would want.
    ///
    /// **It cannot fail.** The resolution is best-effort, so there is no third diagnostic here and
    /// ``failure`` keeps its two — see ``sourceSessions``.
    public func loadSources() async {
        let wanted = Set(repMaxes.map(\.record.sourceSetID))
        guard !wanted.isEmpty else {
            sourceSessions = [:]
            return
        }
        let token = beginRead()
        let resolved = await recomputer.sessionIDs(forSetIDs: wanted, inExerciseID: exerciseID)
        guard isCurrent(token) else { return }
        sourceSessions = resolved
    }

    /// Reloads the estimated one-rep maximum (`FR-1.7.1`).
    ///
    /// **A failure here leaves the previous estimate on screen and says nothing about the list**:
    /// the estimate is one number beside it, and blanking the list because the tile could not be
    /// refreshed reports the wrong thing failed. It does not run the other way either — see
    /// ``failure``.
    public func loadEstimate() async {
        let token = beginRead()
        do {
            let loaded = try await recomputer.estimatedMax(forExerciseID: exerciseID)
            guard isCurrent(token) else { return }
            estimate = loaded
            estimateFailure = nil
            // No `beginRead()` of its own: the link belongs to the estimate just published, and a
            // second token would let a load started in between look like this one.
            let source = await sourceSession(of: loaded)
            guard isCurrent(token) else { return }
            estimateSourceSession = source
        } catch {
            guard isCurrent(token) else { return }
            estimateFailure = String(describing: error)
        }
    }

    /// Where `estimate`'s source set was performed, for the one kind of estimate that has one.
    ///
    /// A computed estimate names exactly one set, so this resolves one identifier rather than the
    /// list ``loadSources()`` resolves — the same walk either way, which is why it is skipped
    /// outright for an override and for an absence.
    private func sourceSession(of estimate: EstimatedMax) async -> UUID? {
        guard let setID = estimate.record?.sourceSetID else { return nil }
        return await recomputer.sessionIDs(forSetIDs: [setID], inExerciseID: exerciseID)[setID]
    }

    /// Sets `FR-1.7.5`'s manual override, or clears it, and shows the result of its own write.
    ///
    /// **It reloads rather than waiting to be told.** The recomputer announces the change and this
    /// state is subscribed to it, but a stream is delivered whenever the runtime gets to it — and a
    /// screen whose own command takes visible effect at some later moment is one the user taps
    /// twice. The announcement still matters: it is what moves the number on every *other* screen.
    ///
    /// - Parameter weight: The number the user entered, or `nil` to return to the computed
    ///   estimate.
    public func setManualEstimate(_ weight: Weight?) async {
        do {
            try await recomputer.setManualEstimate(weight, forExerciseID: exerciseID)
            manualFailure = nil
        } catch {
            manualFailure = String(describing: error)
            return
        }
        await loadEstimate()
    }

    /// Keeps this current until cancelled (`TR-1.5`).
    ///
    /// **A change to another exercise is ignored rather than reloaded**, which is `FR-1.6.4`'s scope
    /// arriving on the read side: every logged set publishes, and a screen that reloaded on all of
    /// them would walk this exercise's history because a different one was trained.
    ///
    /// **A screen that draws no estimate declines it here as well as on its first read.** The
    /// subscription is the path every later change arrives by, so one that reloaded through
    /// ``load()`` would walk the history for a number it never draws each time this exercise moved —
    /// and a settings change, which moves no rep max at all, would wake it for nothing.
    ///
    /// - Parameters:
    ///   - includingRecords: Whether `FR-1.6.1`'s rep maxes and their links are values this
    ///     subscriber draws. `false` is for a screen showing only the estimate, which would
    ///     otherwise re-read a cached list and re-resolve its links on every set logged here.
    ///   - includingEstimate: Whether `FR-1.7.1`'s estimate is one of them. `false` narrows a change
    ///     to the records and their links, and ignores a settings change outright.
    public func observeChanges(
        includingRecords: Bool = true, includingEstimate: Bool = true
    ) async {
        for await change in await recomputer.changes() {
            switch change {
            case .exercise(let changed) where changed == exerciseID:
                if includingRecords {
                    await loadRecords()
                    await loadSources()
                }
                if includingEstimate { await loadEstimate() }
            case .everyExercise where includingEstimate:
                await loadEstimate()
            case .exercise, .everyExercise:
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
