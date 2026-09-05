import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// This exercise's training max, its history, and the one write that changes it (`FR-15.1.1`,
/// `FR-15.1.4`, `FR-15.1.5`, `FR-16.7.2`).
///
/// **A section with a read of its own**, on ``ExerciseEstimateSection``'s rule and for its reason:
/// the training max is a different table from the sets, and a screen that read both in one pass
/// would re-walk a training history because a coach's number was typed.
///
/// **Nothing here is derived** (`OUT-16.2`). `FR-15.1.5`'s one-tap recalculate from the e1RM is
/// deliberately not built, so this state offers no command that computes anything: what it holds is
/// what the lifter entered, and ``RepositoryInterface/TrainingMaxRepository`` is asked which of
/// those is in force.
@Observable
final class TrainingMaxSectionState {
    /// The number in force today, or `nil` where this exercise has never had one.
    ///
    /// **The whole entry rather than the weight**, because `FR-15.1.5`'s indicator is the date and
    /// the note beside it: a number with neither is one the lifter cannot tell from a stale one.
    private(set) var current: TrainingMaxHistoryEntry?

    /// Every change, newest ``RepositoryInterface/TrainingMaxHistoryEntry/effectiveFrom`` first
    /// (`FR-15.1.4`).
    private(set) var history: [TrainingMaxHistoryEntry] = []

    /// Whether the first read has answered — the difference between "no training max" and "not
    /// asked yet", which ``current`` alone cannot carry.
    private(set) var hasLoaded = false

    /// Why the last read failed, or `nil`. A **diagnostic**, not copy (`G-3.4`).
    private(set) var readFailure: String?

    /// Why the last write failed, or `nil`. Its own property, on `ExerciseDetailState`'s rule: a
    /// write that fails leaves the number on screen exactly as it was.
    private(set) var writeFailure: String?

    /// The unit the number is shown and entered in (`G-3.1`) — the section's own read, on the
    /// records section's rule, and kilograms until it lands.
    private(set) var unit: MassUnit = .kilograms

    /// Which exercise this section is about.
    let exerciseID: UUID

    /// The two tables `FR-15.1` is stored in — read for the history, written by ``save(_:)``.
    private let trainingMaxes: any TrainingMaxRepository

    /// Where the display unit comes from.
    private let settings: any SettingsRepository

    /// The app's one announcement channel (`TR-1.5`), told when the number moves so that the
    /// dashboard's tile follows without the tab being revisited.
    private let records: PersonalRecordRecomputer

    /// What "now" is when a write is stamped and when "in force today" is resolved — injectable, so
    /// a test can assert a date rather than wait for one.
    private let now: @Sendable () -> Date

    /// Builds the state over the exercise it reports on.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise's training max to show.
    ///   - trainingMaxes: Where it is stored.
    ///   - settings: The settings row, for the unit the number is shown in.
    ///   - records: The app's one recompute actor, for the announcement a write owes other screens.
    ///   - now: What "today" is.
    init(
        exerciseID: UUID,
        trainingMaxes: any TrainingMaxRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.exerciseID = exerciseID
        self.trainingMaxes = trainingMaxes
        self.settings = settings
        self.records = records
        self.now = now
    }

    /// Reads the number in force and the whole history behind it.
    ///
    /// **Two reads rather than "the first of the history"**, because they are not the same question:
    /// the history is newest-first by `effectiveFrom` and its first row can be one that takes effect
    /// *next* week, which is not what is in force today.
    func load() async {
        do {
            let today = now()
            current = try await trainingMaxes.trainingMax(forExerciseID: exerciseID, on: today)
            history = try await trainingMaxes.history(
                forExerciseID: exerciseID, includingDeleted: false)
            readFailure = nil
        } catch {
            readFailure = String(describing: error)
        }
        hasLoaded = true
    }

    /// Records a change (`FR-15.1.4`, `FR-16.7.2`), and reloads to show it.
    ///
    /// **What it replaces is read at the draft's own date, not taken from ``current``.** A change
    /// backdated to the start of a block replaces whatever was in force *then*, and the number on
    /// screen may be a later one entirely. `nil` where there was none — which is a different
    /// statement from a change from zero, and is why
    /// ``RepositoryInterface/TrainingMaxHistoryEntry/oldWeight`` is optional.
    ///
    /// **It announces after it lands** (`TR-1.5`). Nothing is invalidated — a training max moves no
    /// record — but `FR-15.1.8`'s line under a dashboard tile and `FR-16.7.1`'s percentage are both
    /// drawn from it in other tabs.
    ///
    /// - Parameter draft: What the sheet holds.
    /// - Returns: Whether it was stored, which is what closes the sheet.
    func save(_ draft: TrainingMaxDraft) async -> Bool {
        guard let weight = draft.weight else { return false }
        let day = draft.effectiveDay
        do {
            let replaced = try await trainingMaxes.trainingMax(forExerciseID: exerciseID, on: day)
            let stamp = now()
            try await trainingMaxes.save(
                TrainingMaxHistoryEntry(
                    id: draft.newEntryID,
                    createdAt: stamp,
                    updatedAt: stamp,
                    deletedAt: nil,
                    exerciseID: exerciseID,
                    effectiveFrom: day,
                    oldWeight: replaced?.newWeight,
                    newWeight: weight,
                    reason: draft.trimmedReason))
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
            return false
        }
        await load()
        await records.trainingMaxDidChange(forExerciseID: exerciseID)
        return true
    }

    /// Reads the unit the number is shown in (`G-3.1`).
    ///
    /// A failure leaves it as it was: the section is still readable, and "kg" is the schema's own
    /// default, so it is what a first launch would have found anyway.
    func loadDisplayUnit() async {
        if let stored = try? await settings.settings().displayUnit { unit = stored }
    }

    /// A draft seeded for this exercise, opening on today.
    ///
    /// **It opens empty rather than over the number in force.** A training max is announced by a
    /// coach as a new figure, not adjusted by a nudge from the old one — and a field pre-filled with
    /// the current value invites a save that changes nothing but writes a history row saying it did.
    ///
    /// - Parameters:
    ///   - locale: The locale the field is parsed against (`G-3.4`).
    ///   - calendar: Whose days the date is snapped to.
    /// - Returns: The draft the sheet opens with.
    func newDraft(locale: Locale, calendar: Calendar) -> TrainingMaxDraft {
        TrainingMaxDraft(unit: unit, locale: locale, calendar: calendar, day: now())
    }
}
