import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Settings

/// The bodyweight screen's logic, exercised with no view anywhere in the test (`TR-1.2`).
@Suite("Bodyweight log state")
struct BodyweightLogStateTests {
    @Test("A first load publishes the log newest first")
    func loadPublishesReadingsNewestFirst() async {
        let fakes = InMemoryRepositoryStack()
        await save([(day: 1, kilos: 80), (day: 4, kilos: 82), (day: 9, kilos: 84)], into: fakes.bodyweight)
        let state = logState(over: fakes, today: 9)

        #expect(state.phase == .idle)
        await state.load()

        #expect(readings(of: state).map(\.weight.grams) == [84_000, 82_000, 80_000])
    }

    @Test("Today's average is the window ending now, not the newest reading's")
    func currentAverageUsesToday() async {
        let fakes = InMemoryRepositoryStack()
        await save([(day: 1, kilos: 80), (day: 3, kilos: 82)], into: fakes.bodyweight)

        let thisWeek = logState(over: fakes, today: 5)
        await thisWeek.load()
        #expect(thisWeek.currentAverage == Weight(grams: 81_000))

        // A month later the same two readings are outside the window, and the screen has no
        // current average rather than a stale one.
        let later = logState(over: fakes, today: 28)
        await later.load()
        #expect(later.currentAverage == nil)
        #expect(readings(of: later).count == 2)
    }

    @Test("An empty log loads to no readings and no average")
    func emptyLog() async {
        let state = logState(over: InMemoryRepositoryStack(), today: 9)

        await state.load()

        #expect(state.phase == .loaded([]))
        #expect(state.currentAverage == nil)
        #expect(BodyweightLogScreenState.current(state.phase) == .empty)
    }

    @Test("A failed read leaves the diagnostic on the phase, and the screen offers a retry")
    func failedRead() async {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let state = logState(over: FailingBodyweightRepository(error: failure))

        await state.load()

        #expect(state.phase == .failed(String(describing: failure)))
        #expect(BodyweightLogScreenState.current(state.phase) == .failed)
    }

    @Test("A saved reading is manual, dated to the start of its day, and is read straight back")
    func saveWritesTheReading() async throws {
        let fakes = InMemoryRepositoryStack()
        let state = logState(over: fakes, today: 9)
        await state.load()

        var draft = BodyweightEntryDraft(
            unit: .kilograms,
            locale: Locale(identifier: "en_US"),
            calendar: .gmt,
            day: instant(day: 9, hour: 17)
        )
        draft.weightText = "82.4"

        #expect(await state.save(draft))

        let stored = try #require(
            await fakes.bodyweight.entries(
                in: Date.distantPast...Date.distantFuture, includingDeleted: false
            ).first)
        #expect(stored.weight == Weight(grams: 82_400))
        #expect(stored.source == .manual)
        #expect(stored.date == Calendar.gmt.startOfDay(for: instant(day: 9, hour: 17)))
        #expect(readings(of: state).count == 1)
        #expect(state.writeFailure == nil)
    }

    @Test("A refused draft is not written at all")
    func refusedDraftIsNotWritten() async {
        let fakes = InMemoryRepositoryStack()
        let state = logState(over: fakes, today: 9)
        let draft = BodyweightEntryDraft(
            unit: .kilograms,
            locale: Locale(identifier: "en_US"),
            calendar: .gmt,
            day: instant(day: 9, hour: 8)
        )

        #expect(await state.save(draft) == false)

        let stored =
            await
            (try? fakes.bodyweight.entries(
                in: Date.distantPast...Date.distantFuture, includingDeleted: false)) ?? []
        #expect(stored.isEmpty)
        #expect(state.writeFailure == nil)
    }

    @Test("A failed write keeps the list and reports itself, and the next form opens clean")
    func failedWriteKeepsTheList() async {
        let failure = RepositoryError.identityAlreadyEstablished(recordID: UUID())
        let fakes = InMemoryRepositoryStack()
        await save([(day: 1, kilos: 80), (day: 4, kilos: 82)], into: fakes.bodyweight)
        let repository = FailingBodyweightRepository(error: failure, reads: fakes.bodyweight)
        let state = logState(over: repository, today: 4)
        await state.load()

        var draft = BodyweightEntryDraft(
            unit: .kilograms,
            locale: Locale(identifier: "en_US"),
            calendar: .gmt,
            day: instant(day: 4, hour: 8)
        )
        draft.weightText = "83"

        #expect(await state.save(draft) == false)
        #expect(state.writeFailure == String(describing: failure))
        #expect(readings(of: state).count == 2)

        state.clearWriteFailure()
        #expect(state.writeFailure == nil)
    }

    @Test("The display unit comes from settings, and a settings failure costs only the unit")
    func displayUnitIsRead() async {
        let fakes = InMemoryRepositoryStack()
        let stored = try? await fakes.settings.settings()
        if let stored {
            try? await fakes.settings.save(
                UserSettings(
                    id: stored.id,
                    createdAt: stored.createdAt,
                    updatedAt: stored.updatedAt,
                    deletedAt: stored.deletedAt,
                    userID: stored.userID,
                    displayUnit: .pounds,
                    e1RMFormula: stored.e1RMFormula,
                    theme: stored.theme,
                    defaultRoundingIncrement: stored.defaultRoundingIncrement,
                    defaultRoundingStrategy: stored.defaultRoundingStrategy))
        }
        await save([(day: 1, kilos: 80)], into: fakes.bodyweight)

        let reading = BodyweightLogState(
            repository: fakes.bodyweight,
            settings: fakes.settings,
            calendar: .gmt,
            now: { instant(day: 1, hour: 8) }
        )
        await reading.load()
        #expect(reading.displayUnit == .pounds)

        let unreadable = BodyweightLogState(
            repository: fakes.bodyweight,
            settings: FailingSettingsRepository(),
            calendar: .gmt,
            now: { instant(day: 1, hour: 8) })
        await unreadable.load()
        #expect(unreadable.displayUnit == .kilograms)
        #expect(readings(of: unreadable).count == 1)
    }

    @Test("A load arriving while one is in flight is skipped")
    func loadIsNotReentrant() async {
        // A read that suspends is the whole fixture: with a store that answers straight away the
        // second `load()` always arrives after the first has finished, so the guard cannot be
        // observed at all and a test that removed it would still pass.
        let gate = GatedBodyweightRepository()
        let state = BodyweightLogState(
            repository: gate,
            settings: InMemoryRepositoryStack().settings,
            calendar: .gmt,
            now: { instant(day: 1, hour: 12) })

        let first = Task { await state.load() }
        await settle(until: { gate.reads > 0 })
        #expect(gate.reads == 1, "the first load never reached the store")

        // In its own task, and not awaited here: a second load that is *not* skipped suspends in
        // the store like the first one, and a test that awaited it would hang rather than fail.
        let second = Task { await state.load() }
        await settle(until: { gate.reads > 1 })

        #expect(gate.reads == 1)

        gate.release()
        await first.value
        await second.value
        #expect(state.phase == .loaded([]))
        #expect(gate.reads == 1)
    }

    @Test("A load after one has finished re-reads rather than being skipped")
    func loadRunsAgainOnceTheFirstHasAnswered() async {
        let fakes = InMemoryRepositoryStack()
        let state = logState(over: fakes, today: 4)

        await state.load()
        #expect(state.phase == .loaded([]))

        // The guard is on `.loading`, not on a completed read — which is what makes the screen
        // pick up a reading written somewhere else.
        await save([(day: 4, kilos: 82)], into: fakes.bodyweight)
        await state.load()
        #expect(readings(of: state).count == 1)
    }

    @Test("Loading is the state before the first read answers")
    func loadingIsTheOpeningState() {
        #expect(BodyweightLogScreenState.current(.idle) == .loading)
        #expect(BodyweightLogScreenState.current(.loading) == .loading)
    }
}

// MARK: - Fixtures

/// A state over `fakes`, pinned to a day in February 2024 so no test chases the week it runs in.
private func logState(over fakes: InMemoryRepositoryStack, today: Int) -> BodyweightLogState {
    BodyweightLogState(
        repository: fakes.bodyweight,
        settings: fakes.settings,
        calendar: .gmt,
        now: { instant(day: today, hour: 12) })
}

/// A state over a repository that is not the fakes' — a failing one, usually.
private func logState(
    over repository: any BodyweightRepository, today: Int = 9
) -> BodyweightLogState {
    BodyweightLogState(
        repository: repository,
        settings: InMemoryRepositoryStack().settings,
        calendar: .gmt,
        now: { instant(day: today, hour: 12) })
}

/// The rows a state is publishing, or none.
private func readings(of state: BodyweightLogState) -> [BodyweightReading] {
    guard case .loaded(let readings) = state.phase else { return [] }
    return readings
}

/// Writes readings into the log.
///
/// A list rather than a `[weight: day]` dictionary: two readings at the same weight are ordinary,
/// and keying on the weight would silently write one of them.
private func save(
    _ readings: [(day: Int, kilos: Int)], into repository: any BodyweightRepository
) async {
    for (day, weight) in readings {
        let stamp = instant(day: day, hour: 8)
        try? await repository.save(
            BodyweightEntry(
                id: UUID(
                    uuidString: "B0DE0000-0000-4000-8000-0000000000\(String(format: "%02d", day))")
                    ?? UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                date: stamp,
                weight: Weight(grams: weight * 1000),
                source: .manual))
    }
}

/// A February 2024 instant in GMT.
private func instant(day: Int, hour: Int) -> Date {
    var components = DateComponents()
    components.year = 2024
    components.month = 2
    components.day = day
    components.hour = hour
    return Calendar.gmt.date(from: components) ?? .distantPast
}

/// A log that fails whichever half the test asks it to, reading through to a real one where it is
/// given one — which is what lets a failed *write* be tested over a list that is really there.
private struct FailingBodyweightRepository: BodyweightRepository {
    let error: RepositoryError
    var reads: (any BodyweightRepository)?

    func entries(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [BodyweightEntry] {
        guard let reads else { throw error }
        return try await reads.entries(in: range, includingDeleted: includingDeleted)
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> BodyweightEntry? {
        guard let reads else { throw error }
        return try await reads.entry(id: id, includingDeleted: includingDeleted)
    }

    func save(_ entry: BodyweightEntry) async throws { throw error }

    func deleteEntry(id: UUID) async throws { throw error }
}

/// Runs the scheduler until `condition` holds, or until it clearly never will.
///
/// Bounded rather than open: a condition that never comes true is a failed assertion below, never a
/// suite that hangs.
private func settle(until condition: () -> Bool) async {
    for _ in 0..<1_000 where !condition() {
        await Task.yield()
    }
}

/// A log whose read suspends until it is released, so a second `load()` really does arrive while
/// the first one is still in flight.
///
/// `MainActor`-isolated like everything else in this module, which is the point: both loads run on
/// the same actor and the first one's suspension is what lets the second one start.
@MainActor
private final class GatedBodyweightRepository: BodyweightRepository {
    /// How many reads have reached the store.
    private(set) var reads = 0

    private var waiting: [CheckedContinuation<Void, Never>] = []

    private var isReleased = false

    func entries(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [BodyweightEntry] {
        reads += 1
        guard !isReleased else { return [] }
        await withCheckedContinuation { waiting.append($0) }
        return []
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> BodyweightEntry? { nil }

    func save(_ entry: BodyweightEntry) async throws {}

    func deleteEntry(id: UUID) async throws {}

    /// Lets every suspended read finish, and every later one through.
    func release() {
        isReleased = true
        let waiters = waiting
        waiting.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

/// A settings row that cannot be read, for the clause that says the unit degrades and the list does
/// not.
private struct FailingSettingsRepository: SettingsRepository {
    func settings() async throws -> UserSettings {
        throw RepositoryError.recordNotFound(id: UUID())
    }

    func save(_ settings: UserSettings) async throws {
        throw RepositoryError.recordNotFound(id: settings.id)
    }

    func restorePreferences(from backup: UserSettings) async throws {
        throw RepositoryError.recordNotFound(id: backup.id)
    }
}
