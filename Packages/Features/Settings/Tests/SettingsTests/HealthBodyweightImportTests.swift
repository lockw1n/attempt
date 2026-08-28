import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Settings

/// `FR-1.8.2`'s de-duplication, decided before anything is written.
@Suite("Health bodyweight import")
struct HealthBodyweightImportTests {
    @Test("A day with no reading takes the sample, at its own instant and as a HealthKit row")
    func newDayIsImported() throws {
        let sample = sample(day: 4, hour: 7, kilos: 82.4)

        let plan = plan(samples: [sample], existing: [])

        let entry = try #require(plan.entries.first)
        #expect(plan.entries.count == 1)
        #expect(entry.id == sample.id)
        #expect(entry.source == .healthKit)
        #expect(entry.weight == Weight(grams: 82_400))
        // The scale's own instant, not the start of the day: it is when the reading happened.
        #expect(entry.date == sample.date)
        #expect(entry.date != Calendar.gmt.startOfDay(for: sample.date))
        #expect(entry.createdAt == now)
        #expect(entry.updatedAt == now)
        #expect(entry.deletedAt == nil)
        #expect(plan.daysAlreadyEntered == 0)
    }

    @Test("A day the lifter typed is left alone, whatever the sample says")
    func manualDayWins() {
        let existing = entry(day: 4, hour: 0, kilos: 80, source: .manual)

        let plan = plan(samples: [sample(day: 4, hour: 7, kilos: 82.4)], existing: [existing])

        #expect(plan.entries.isEmpty)
        #expect(plan.daysAlreadyEntered == 1)
    }

    @Test("A morning that synced three times weighs once, and it is the last reading")
    func oneRowPerDay() throws {
        let plan = plan(
            samples: [
                sample(day: 4, hour: 6, kilos: 83.0),
                sample(day: 4, hour: 7, kilos: 82.4),
                sample(day: 4, hour: 5, kilos: 84.0),
            ],
            existing: [])

        #expect(plan.entries.count == 1)
        #expect(try #require(plan.entries.first).weight == Weight(grams: 82_400))
    }

    @Test("Importing the same samples twice writes nothing the second time")
    func reimportIsIdempotent() {
        let samples = [sample(day: 4, hour: 7, kilos: 82.4), sample(day: 5, hour: 7, kilos: 82.0)]
        let first = plan(samples: samples, existing: [])
        #expect(first.entries.count == 2)

        let second = plan(samples: samples, existing: first.entries)

        // Nothing changed, so nothing is written: an unconditional save would restamp `updatedAt`,
        // which is G-2.4's conflict key.
        #expect(second.entries.isEmpty)
        #expect(second.daysAlreadyEntered == 0)
    }

    @Test("A later reading on an imported day replaces that row rather than joining it")
    func laterSampleReplacesInPlace() throws {
        let first = plan(samples: [sample(day: 4, hour: 6, kilos: 83.0)], existing: [])
        let imported = try #require(first.entries.first)

        let second = plan(
            samples: [sample(day: 4, hour: 6, kilos: 83.0), sample(day: 4, hour: 9, kilos: 82.4)],
            existing: [imported],
            at: later)

        let replacement = try #require(second.entries.first)
        #expect(second.entries.count == 1)
        #expect(replacement.id == imported.id)
        // Created when the row first appeared, updated when this import moved it.
        #expect(replacement.createdAt == now)
        #expect(replacement.updatedAt == later)
        #expect(replacement.weight == Weight(grams: 82_400))
    }

    @Test("A reading that was deleted is not brought back")
    func deletedDayIsNotResurrected() {
        var deleted = entry(day: 4, hour: 7, kilos: 82, source: .healthKit)
        deleted = BodyweightEntry(
            id: deleted.id,
            createdAt: deleted.createdAt,
            updatedAt: deleted.updatedAt,
            deletedAt: now,
            date: deleted.date,
            weight: deleted.weight,
            source: deleted.source)

        let plan = plan(samples: [sample(day: 4, hour: 8, kilos: 82.4)], existing: [deleted])

        #expect(plan.entries.isEmpty)
        #expect(plan.daysAlreadyEntered == 1)
    }

    @Test("A sample whose id belongs to some other row is dropped, never written over it")
    func aTakenIdentityIsNotOverwritten() {
        // The manual row is on a different day, so the day rule does not save it — only the
        // identity check does, and without it this import would replace a reading the user typed.
        let manual = entry(day: 1, hour: 0, kilos: 80, source: .manual)
        let collides = BodyweightSample(
            id: manual.id, date: instant(day: 4, hour: 7), weight: Weight(grams: 82_400))

        let plan = plan(samples: [collides], existing: [manual])

        #expect(plan.entries.isEmpty)
        #expect(plan.daysAlreadyEntered == 0)
    }

    @Test("Days already entered are counted once each, however many samples fell on them")
    func skippedDaysAreCountedByDay() {
        let existing = [
            entry(day: 4, hour: 0, kilos: 80, source: .manual),
            entry(day: 5, hour: 0, kilos: 81, source: .manual),
        ]

        let plan = plan(
            samples: [
                sample(day: 4, hour: 6, kilos: 83.0),
                sample(day: 4, hour: 7, kilos: 82.4),
                sample(day: 5, hour: 7, kilos: 82.0),
            ],
            existing: existing)

        #expect(plan.entries.isEmpty)
        #expect(plan.daysAlreadyEntered == 2)
    }

    @Test("The plan comes out oldest first, whatever order the samples arrived in")
    func planIsOrdered() {
        let plan = plan(
            samples: [
                sample(day: 9, hour: 7, kilos: 84),
                sample(day: 1, hour: 7, kilos: 80),
                sample(day: 4, hour: 7, kilos: 82),
            ],
            existing: [])

        #expect(plan.entries.map(\.weight.grams) == [80_000, 82_000, 84_000])
    }

    @Test("Two live imported rows on one day: one is replaced, the lowest-identified of them")
    func aDayCarryingTwoImportedRowsReplacesOne() throws {
        // A state this planner cannot produce — it writes one row a day — but a store it did not
        // write may hold it (a restore, a merge), which is what the tie-break is for. Pinned so
        // the branch has a defined answer rather than an accidental one.
        let existing = [
            entry(day: 4, hour: 6, kilos: 80, source: .healthKit),
            entry(day: 4, hour: 7, kilos: 81, source: .healthKit),
        ]

        let plan = plan(samples: [sample(day: 4, hour: 9, kilos: 82.4)], existing: existing)

        #expect(plan.entries.count == 1)
        let written = try #require(plan.entries.first)
        // The lower identifier wins, whichever order the rows arrived in.
        #expect(written.id == existing.map(\.id).min { $0.uuidString < $1.uuidString })
        #expect(written.weight == Weight(grams: 82_400))
        #expect(plan.daysAlreadyEntered == 0)
    }

    @Test("A reading typed on an imported day retires that day's imported row")
    func typedReadingSupersedesTheImport() {
        let imported = entry(day: 4, hour: 7, kilos: 82, source: .healthKit)
        let typed = entry(day: 4, hour: 0, kilos: 80, source: .manual)

        let retired = HealthBodyweightImport.supersededImports(
            by: typed, in: [imported, typed], calendar: .gmt)

        // FR-1.8.3 averages readings and not days, so leaving both would weigh 4 Feb twice.
        #expect(retired == [imported.id])
    }

    @Test("Superseding reaches only that day, only imports, and only live ones")
    func supersedingIsNarrow() {
        let typed = entry(day: 4, hour: 0, kilos: 80, source: .manual)
        let otherDay = entry(day: 5, hour: 7, kilos: 82, source: .healthKit)
        let alsoTyped = entry(day: 4, hour: 9, kilos: 81, source: .manual)
        let tombstoned = BodyweightEntry(
            id: identity(prefix: "DE", day: 4, hour: 8),
            createdAt: now,
            updatedAt: now,
            deletedAt: now,
            date: instant(day: 4, hour: 8),
            weight: Weight(grams: 83_000),
            source: .healthKit)

        let retired = HealthBodyweightImport.supersededImports(
            by: typed, in: [otherDay, alsoTyped, tombstoned, typed], calendar: .gmt)

        // A day the lifter typed twice is theirs to sort out; a tombstone is already retired.
        #expect(retired.isEmpty)
    }

    @Test("An imported reading supersedes nothing — only a typed one wins the day")
    func anImportSupersedesNothing() {
        let first = entry(day: 4, hour: 6, kilos: 82, source: .healthKit)
        let second = entry(day: 4, hour: 7, kilos: 83, source: .healthKit)

        #expect(
            HealthBodyweightImport.supersededImports(
                by: second, in: [first, second], calendar: .gmt
            ).isEmpty)
    }

    @Test("Nothing to import from an empty source, over a log that stays untouched")
    func nothingToImport() {
        let plan = plan(samples: [], existing: [entry(day: 4, hour: 0, kilos: 80, source: .manual)])

        #expect(plan.entries.isEmpty)
        #expect(plan.daysAlreadyEntered == 0)
    }
}

// MARK: - Fixtures

/// When every plan in this suite is made.
private let now = instant(day: 20, hour: 12)

/// A second, later import.
private let later = instant(day: 21, hour: 12)

/// A plan over GMT days.
private func plan(
    samples: [BodyweightSample], existing: [BodyweightEntry], at moment: Date = now
) -> HealthBodyweightImport.Plan {
    HealthBodyweightImport.plan(
        samples: samples, existing: existing, calendar: .gmt, now: moment)
}

/// A sample, its identity derived from its day and hour so a test can predict it.
private func sample(day: Int, hour: Int, kilos: Double) -> BodyweightSample {
    BodyweightSample(
        id: identity(prefix: "5A", day: day, hour: hour),
        date: instant(day: day, hour: hour),
        weight: Weight(kilograms: kilos, rounding: .nearest) ?? .zero)
}

/// A row already in the log.
private func entry(
    day: Int, hour: Int, kilos: Int, source: BodyweightSource
) -> BodyweightEntry {
    let stamp = instant(day: day, hour: hour)
    return BodyweightEntry(
        id: identity(prefix: "B0", day: day, hour: hour),
        createdAt: stamp,
        updatedAt: stamp,
        deletedAt: nil,
        date: stamp,
        weight: Weight(grams: kilos * 1000),
        source: source)
}

/// A predictable identifier.
private func identity(prefix: String, day: Int, hour: Int) -> UUID {
    UUID(
        uuidString: "\(prefix)DE0000-0000-4000-8000-0000\(String(format: "%04d%04d", day, hour))")
        ?? UUID()
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
