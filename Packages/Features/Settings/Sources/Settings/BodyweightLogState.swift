import Foundation
import PowerliftingCore
import RepositoryInterface

/// The bodyweight log's data and every operation on it (`FR-1.8.1`, `FR-1.8.3`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on ``SettingsLandingState``'s rule:
/// the log is read and written from this screen alone and lives exactly as long as it does.
///
/// **One read answers both halves.** The history list and the current seven-day average are the
/// same rows seen twice, so asking the store a second time for the window would be a second walk for
/// an answer already in hand — and the two could then disagree about what was last weighed.
///
/// **A failed write never costs the screen its list**, on the same rule the settings landing and the
/// gyms both follow: the read's outcome and the last write's outcome are separate properties.
@Observable
final class BodyweightLogState {
    /// What the screen has to show, as one value rather than three flags.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// A read is in flight.
        case loading

        /// The log, newest first (`FR-1.8.3`), each row carrying its own window's average.
        case loaded([BodyweightReading])

        /// The read failed, carrying the error's description — a **diagnostic**, not copy
        /// (`G-3.4`). Recoverable: ``load()`` runs again from here, which is the retry.
        case failed(String)
    }

    /// The screen's read state.
    private(set) var phase: Phase = .idle

    /// The seven-day average ending **today**, or `nil` when this week holds too few readings.
    ///
    /// Today's window rather than the newest reading's: a lifter who last weighed in three weeks ago
    /// has no current average, and drawing that old window's figure would present it as one.
    private(set) var currentAverage: Weight?

    /// The last write that failed, as the error's description, or `nil` once one succeeds. A
    /// **diagnostic**, not copy (`G-3.4`).
    private(set) var writeFailure: String?

    /// The unit readings are shown and entered in (`G-3.1`).
    private(set) var displayUnit: MassUnit = .kilograms

    @ObservationIgnored private let repository: any BodyweightRepository

    @ObservationIgnored private let settings: any SettingsRepository

    /// Whose days the seven-day window is measured in (`G-3.4`).
    @ObservationIgnored let calendar: Calendar

    /// What "now" is. Injected so a test can pin a week rather than chase the one it runs in.
    @ObservationIgnored private let now: () -> Date

    /// Builds the state over the repositories it reads and writes through.
    ///
    /// - Parameters:
    ///   - repository: The bodyweight log.
    ///   - settings: Where the display unit comes from.
    ///   - calendar: Whose days the window is measured in. Defaults to the user's.
    ///   - now: What day it is. Defaults to the clock.
    init(
        repository: any BodyweightRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    /// Reads the whole log, then derives the rows and today's average from it.
    ///
    /// **Unbounded, deliberately.** `FR-1.8.3`'s list is the whole history and a lifter logs at most
    /// one row a day, so the read is a few hundred rows where the session list's is a walk over
    /// every set — `NFR-1.6`'s formal number is `T-1.83`'s, and this is the caller to measure there
    /// if any is.
    ///
    /// **A settings read that fails costs the unit and not the screen**: kilograms is a wrong label
    /// on a real list, where a refused read is no list at all.
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        if let unit = try? await settings.settings().displayUnit { displayUnit = unit }
        do {
            let entries = try await repository.entries(
                in: Date.distantPast...Date.distantFuture, includingDeleted: false)
            currentAverage = BodyweightAverage.rolling(
                endingOn: now(), over: entries, calendar: calendar)
            phase = .loaded(BodyweightAverage.readings(from: entries, calendar: calendar))
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Writes a reading — `FR-1.8.1`'s manual entry, with its own date.
    ///
    /// - Parameter draft: The form's contents.
    /// - Returns: Whether the write landed. `false` leaves the form open over ``writeFailure``.
    @discardableResult
    func save(_ draft: BodyweightEntryDraft) async -> Bool {
        guard let entry = draft.entry() else { return false }
        do {
            try await repository.save(entry)
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
            return false
        }
        await reload()
        return true
    }

    /// Retires the last failure, so a form opening does not report a failure from before it.
    func clearWriteFailure() {
        writeFailure = nil
    }

    /// A read that is not skipped by the in-flight guard, for use straight after a write.
    private func reload() async {
        phase = .idle
        await load()
    }
}

/// Which of `FR-1.13.1`'s states the bodyweight screen is in.
///
/// A resolver rather than a chain of `if let` inside the view, on this module's rule: which state
/// was chosen is a unit test's question, and what it looks like is a snapshot's.
///
/// **No `Offline`** — the log is local rows (`G-2.1`). The insufficiency `FR-1.13.3` asks for is not
/// a state of this screen but of the average card on it: a list of real readings is never
/// insufficient, while the trend drawn from them can be.
enum BodyweightLogScreenState: Equatable {
    /// The log has not been read yet.
    case loading

    /// The read answered and nothing has ever been weighed — `FR-1.13.2`'s first-launch case, whose
    /// action is the only thing that makes a first reading.
    case empty

    /// There are readings to show, newest first.
    case ready([BodyweightReading])

    /// The log could not be read; a retry may work.
    case failed

    /// Which state a phase is.
    ///
    /// - Parameter phase: The screen's read state.
    /// - Returns: The state to draw.
    static func current(_ phase: BodyweightLogState.Phase) -> Self {
        switch phase {
        case .idle, .loading: .loading
        case .loaded(let readings): readings.isEmpty ? .empty : .ready(readings)
        case .failed: .failed
        }
    }
}
