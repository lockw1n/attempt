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

    /// What `FR-1.8.2`'s import has done, as one value rather than a flag and a count.
    enum HealthImport: Equatable {
        /// No import has run in this screen's lifetime. Nothing moves back to it: a second
        /// import goes straight to ``importing`` over whatever the last one reported.
        case idle

        /// An import is in flight — the authorization request included.
        case importing

        /// An import finished: how many rows it wrote, and how many of its days the log already
        /// had. **Neither number says whether access was granted** — see
        /// ``BodyweightSampleSource/authorize()``, which is why zero and zero is reported as
        /// nothing new rather than as a refusal.
        case imported(added: Int, daysAlreadyEntered: Int)

        /// The import failed, carrying the error's description — a **diagnostic**, not copy
        /// (`G-3.4`).
        case failed(String)
    }

    /// The screen's read state.
    private(set) var phase: Phase = .idle

    /// What the last import did, or `idle` where none has run.
    private(set) var healthImport: HealthImport = .idle

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

    /// Where `FR-1.8.2`'s readings come from, or `nil` where this build has no source to offer.
    @ObservationIgnored private let health: (any BodyweightSampleSource)?

    /// Whose days the seven-day window is measured in (`G-3.4`).
    @ObservationIgnored let calendar: Calendar

    /// What "now" is. Injected so a test can pin a week rather than chase the one it runs in.
    @ObservationIgnored private let now: () -> Date

    /// Builds the state over the repositories it reads and writes through.
    ///
    /// - Parameters:
    ///   - repository: The bodyweight log.
    ///   - settings: Where the display unit comes from.
    ///   - health: `FR-1.8.2`'s sample source. `nil` leaves the import command off the screen
    ///     entirely, which is what a build with no health framework draws.
    ///   - calendar: Whose days the window is measured in. Defaults to the user's.
    ///   - now: What day it is. Defaults to the clock.
    init(
        repository: any BodyweightRepository,
        settings: any SettingsRepository,
        health: (any BodyweightSampleSource)? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.settings = settings
        self.health = health
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
        // Past here the reading is written, so a failure is reported *and the confirmation kept*:
        // returning `false` would reopen the form over a row that already exists, and confirming
        // it a second time would write the day twice — the duplicate this whole step removes.
        do {
            try await retireImports(supersededBy: entry)
        } catch {
            writeFailure = String(describing: error)
        }
        await reload()
        return true
    }

    /// Retires the imported rows a typed reading has replaced (`FR-1.8.2`).
    ///
    /// The rule itself is ``HealthBodyweightImport/supersededImports(by:in:calendar:)`` — the
    /// import's day rule owns both directions, so neither can drift from the other.
    ///
    /// - Parameter entry: The reading just written.
    private func retireImports(supersededBy entry: BodyweightEntry) async throws {
        let live = try await repository.entries(
            in: Date.distantPast...Date.distantFuture, includingDeleted: false)
        let retired = HealthBodyweightImport.supersededImports(
            by: entry, in: live, calendar: calendar)
        for id in retired {
            try await repository.deleteEntry(id: id)
        }
    }

    /// Retires the last failure, so a form opening does not report a failure from before it.
    func clearWriteFailure() {
        writeFailure = nil
    }

    /// Whether this screen has an import to offer at all (`FR-1.8.2`).
    ///
    /// The command is absent rather than disabled where it is `false`: a device with no health data
    /// on it has nothing to explain, and a dimmed button that can never be pressed is a question the
    /// user cannot answer.
    var isHealthImportAvailable: Bool { health?.isAvailable ?? false }

    /// `FR-1.8.2`: asks for body mass, de-duplicates it against the log, and writes what is new.
    ///
    /// **The prompt is here and nowhere earlier** (`TR-1.9`): nothing calls this until a person asks
    /// for an import, so launching the app asks for no health access.
    ///
    /// **The log is read with its tombstones**, which the screen's own read is not: a day whose
    /// reading was deleted must not come back on the next import. See ``HealthBodyweightImport``.
    ///
    /// **A failure never costs the screen its list**, ``save(_:)``'s rule: the outcome lands on
    /// ``healthImport`` and the rows are re-read only if something was actually written.
    func importFromHealth() async {
        guard let health, health.isAvailable, healthImport != .importing else { return }
        healthImport = .importing
        var written = 0
        do {
            try await health.authorize()
            let samples = try await health.samples()
            let existing = try await repository.entries(
                in: Date.distantPast...Date.distantFuture, includingDeleted: true)
            let plan = HealthBodyweightImport.plan(
                samples: samples, existing: existing, calendar: calendar, now: now())
            for entry in plan.entries {
                try await repository.save(entry)
                written += 1
            }
            healthImport = .imported(
                added: written, daysAlreadyEntered: plan.daysAlreadyEntered)
        } catch {
            healthImport = .failed(String(describing: error))
        }
        if written > 0 { await reload() }
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
