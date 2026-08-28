import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Settings

/// `FR-1.8.2`'s import as the screen runs it — the prompt, the write, and what it reports.
///
/// A file of its own rather than more of `BodyweightLogStateTests`: that suite is the manual half
/// (`FR-1.8.1`, `FR-1.8.3`) and had reached this module's file-length cap. The de-duplication rule
/// itself is `HealthBodyweightImportTests`; what is here is the state around it.
@Suite("Bodyweight health import")
struct BodyweightHealthImportStateTests {
    @Test("Nothing asks for health access until the import command is used")
    func authorizationIsNotRequestedAtLaunch() async {
        let source = StubSampleSource(samples: [healthSample(day: 4, hour: 7, kilos: 82.4)])
        let state = logState(over: InMemoryRepositoryStack(), today: 4, health: source)

        await state.load()

        // TR-1.9: the screen reading its log is not a reason to prompt.
        #expect(source.authorizations == 0)
        #expect(source.reads == 0)
        #expect(state.healthImport == .idle)

        await state.importFromHealth()
        #expect(source.authorizations == 1)
    }

    @Test("An import writes the new days, keeps the typed ones, and the list picks it up")
    func importWritesAndReloads() async {
        let fakes = InMemoryRepositoryStack()
        await save([(day: 4, kilos: 80)], into: fakes.bodyweight)
        let source = StubSampleSource(samples: [
            healthSample(day: 4, hour: 7, kilos: 83.0),
            healthSample(day: 5, hour: 7, kilos: 82.4),
        ])
        let state = logState(over: fakes, today: 5, health: source)
        await state.load()

        await state.importFromHealth()

        #expect(state.healthImport == .imported(added: 1, daysAlreadyEntered: 1))
        #expect(readings(of: state).map(\.weight.grams) == [82_400, 80_000])
    }

    @Test("A source that refuses leaves the log alone and reports itself")
    func importFailureKeepsTheList() async {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let fakes = InMemoryRepositoryStack()
        await save([(day: 4, kilos: 80)], into: fakes.bodyweight)
        let source = StubSampleSource(samples: [], failure: failure)
        let state = logState(over: fakes, today: 4, health: source)
        await state.load()

        await state.importFromHealth()

        #expect(state.healthImport == .failed(String(describing: failure)))
        #expect(readings(of: state).count == 1)
        #expect(BodyweightLogScreenState.current(state.phase) == .ready(readings(of: state)))
    }

    @Test("A source with nothing in it is reported as nothing new, never as a refusal")
    func importOfNothing() async {
        let source = StubSampleSource(samples: [])
        let state = logState(over: InMemoryRepositoryStack(), today: 4, health: source)
        await state.load()

        await state.importFromHealth()

        // A declined read authorization is indistinguishable from an empty source, so this is the
        // only honest thing the screen can say.
        #expect(state.healthImport == .imported(added: 0, daysAlreadyEntered: 0))
    }

    @Test("No source, or one this device does not have, offers no command and does nothing")
    func unavailableSourceIsAbsent() async {
        let without = logState(over: InMemoryRepositoryStack(), today: 4)
        #expect(without.isHealthImportAvailable == false)
        await without.importFromHealth()
        #expect(without.healthImport == .idle)

        let source = StubSampleSource(
            samples: [healthSample(day: 4, hour: 7, kilos: 82.4)], isAvailable: false)
        let unavailable = logState(over: InMemoryRepositoryStack(), today: 4, health: source)
        #expect(unavailable.isHealthImportAvailable == false)

        await unavailable.importFromHealth()

        #expect(unavailable.healthImport == .idle)
        #expect(source.authorizations == 0)
    }

    @Test("A reading that was deleted is not imported back")
    func importDoesNotResurrectADeletedReading() async throws {
        let fakes = InMemoryRepositoryStack()
        await save([(day: 4, kilos: 80)], into: fakes.bodyweight)
        let stored = try #require(
            await fakes.bodyweight.entries(
                in: Date.distantPast...Date.distantFuture, includingDeleted: false
            ).first)
        try await fakes.bodyweight.deleteEntry(id: stored.id)

        let source = StubSampleSource(samples: [healthSample(day: 4, hour: 7, kilos: 82.4)])
        let state = logState(over: fakes, today: 4, health: source)
        await state.load()
        #expect(readings(of: state).isEmpty)

        await state.importFromHealth()

        // The tombstone is only visible to a read that asks for it — this is what pins the
        // import's `includingDeleted: true`, which the screen's own read deliberately is not.
        #expect(state.healthImport == .imported(added: 0, daysAlreadyEntered: 1))
        #expect(readings(of: state).isEmpty)
    }

    @Test("Typing a reading on a day already imported leaves that day one row, the typed one")
    func typedReadingRetiresTheImportedRow() async throws {
        let fakes = InMemoryRepositoryStack()
        let source = StubSampleSource(samples: [healthSample(day: 4, hour: 7, kilos: 82.4)])
        let state = logState(over: fakes, today: 4, health: source)
        await state.load()
        await state.importFromHealth()
        #expect(state.healthImport == .imported(added: 1, daysAlreadyEntered: 0))

        // The lifter now types 4 Feb by hand, after the import rather than before it.
        var draft = BodyweightEntryDraft(
            unit: .kilograms,
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: .gmt,
            day: instant(day: 4, hour: 12))
        draft.weightText = "80"
        #expect(await state.save(draft))

        let live = try await fakes.bodyweight.entries(
            in: Date.distantPast...Date.distantFuture, includingDeleted: false)
        #expect(live.count == 1)
        #expect(try #require(live.first).source == .manual)
        #expect(try #require(live.first).weight == Weight(grams: 80_000))
        // Both rows live would have averaged 81.2 kg — a number neither reading says.
        #expect(readings(of: state).map(\.weight.grams) == [80_000])
        #expect(state.writeFailure == nil)
    }

    @Test("The retired row is a tombstone, so the next import does not write it back")
    func aSupersededImportIsNotReimported() async throws {
        let fakes = InMemoryRepositoryStack()
        let source = StubSampleSource(samples: [healthSample(day: 4, hour: 7, kilos: 82.4)])
        let state = logState(over: fakes, today: 4, health: source)
        await state.load()
        await state.importFromHealth()
        var draft = BodyweightEntryDraft(
            unit: .kilograms,
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: .gmt,
            day: instant(day: 4, hour: 12))
        draft.weightText = "80"
        #expect(await state.save(draft))

        await state.importFromHealth()

        // The day is the lifter's now, on both of the day rule's halves.
        #expect(state.healthImport == .imported(added: 0, daysAlreadyEntered: 1))
        let live = try await fakes.bodyweight.entries(
            in: Date.distantPast...Date.distantFuture, includingDeleted: false)
        #expect(live.count == 1)
        #expect(try #require(live.first).source == .manual)
    }

    @Test("An import arriving while one is in flight is skipped")
    func importIsNotReentrant() async {
        // A source that suspends is the whole fixture, for the reason `loadIsNotReentrant` gives:
        // with one that answers straight away the second call always arrives after the first has
        // finished, and a test that removed the guard would still pass.
        let gate = GatedSampleSource()
        let state = logState(over: InMemoryRepositoryStack(), today: 4, health: gate)

        let first = Task { await state.importFromHealth() }
        await settle(until: { gate.authorizations > 0 })
        #expect(gate.authorizations == 1, "the first import never reached the source")
        #expect(state.healthImport == .importing)

        // In its own task and not awaited here: a second import that is *not* skipped suspends in
        // the source like the first one, and awaiting it would hang rather than fail.
        let second = Task { await state.importFromHealth() }
        await settle(until: { gate.authorizations > 1 })

        #expect(gate.authorizations == 1)

        gate.release()
        await first.value
        await second.value
        #expect(state.healthImport == .imported(added: 0, daysAlreadyEntered: 0))
        #expect(gate.authorizations == 1)
    }
}

// MARK: - Fixtures

/// A state over `fakes` with `FR-1.8.2`'s source behind it.
private func logState(
    over fakes: InMemoryRepositoryStack, today: Int, health: any BodyweightSampleSource
) -> BodyweightLogState {
    BodyweightLogState(
        repository: fakes.bodyweight,
        settings: fakes.settings,
        health: health,
        calendar: .gmt,
        now: { instant(day: today, hour: 12) })
}

/// A sample as a source would report it.
private func healthSample(day: Int, hour: Int, kilos: Double) -> BodyweightSample {
    BodyweightSample(
        id: UUID(
            uuidString: "5ADE0000-0000-4000-8000-0000\(String(format: "%04d%04d", day, hour))")
            ?? UUID(),
        date: instant(day: day, hour: hour),
        weight: Weight(kilograms: kilos, rounding: .nearest) ?? .zero)
}

/// A source that answers straight away, counting what was asked of it.
private final class StubSampleSource: BodyweightSampleSource {
    let disclosed: [BodyweightSample]
    let failure: (any Error)?
    let isAvailable: Bool

    /// How many times the prompt was asked for.
    private(set) var authorizations = 0

    /// How many times the samples were read.
    private(set) var reads = 0

    init(samples: [BodyweightSample], failure: (any Error)? = nil, isAvailable: Bool = true) {
        self.disclosed = samples
        self.failure = failure
        self.isAvailable = isAvailable
    }

    func authorize() async throws {
        authorizations += 1
        if let failure { throw failure }
    }

    func samples() async throws -> [BodyweightSample] {
        reads += 1
        return disclosed
    }
}

/// A source whose authorization suspends until it is released, so a second import really does
/// arrive while the first is still in flight.
@MainActor
private final class GatedSampleSource: BodyweightSampleSource {
    /// How many prompts have reached the source.
    private(set) var authorizations = 0

    private var waiting: [CheckedContinuation<Void, Never>] = []

    private var isReleased = false

    let isAvailable = true

    func authorize() async {
        authorizations += 1
        guard !isReleased else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func samples() async -> [BodyweightSample] { [] }

    /// Lets every suspended request finish, and every later one through.
    func release() {
        isReleased = true
        let waiters = waiting
        waiting.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

/// The rows a state is publishing, or none.
private func readings(of state: BodyweightLogState) -> [BodyweightReading] {
    guard case .loaded(let readings) = state.phase else { return [] }
    return readings
}

/// A state with no source at all behind it.
private func logState(over fakes: InMemoryRepositoryStack, today: Int) -> BodyweightLogState {
    BodyweightLogState(
        repository: fakes.bodyweight,
        settings: fakes.settings,
        calendar: .gmt,
        now: { instant(day: today, hour: 12) })
}

/// Writes manual readings into the log.
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

/// Runs the scheduler until `condition` holds, or until it clearly never will.
private func settle(until condition: () -> Bool) async {
    for _ in 0..<1_000 where !condition() {
        await Task.yield()
    }
}
