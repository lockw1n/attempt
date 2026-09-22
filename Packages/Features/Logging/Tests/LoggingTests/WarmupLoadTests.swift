import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-18.6.8` and `DOD-18.13`: a section's load is its **working** sets', and a warm-up stored at
/// its own load keeps it through a rewrite.
///
/// **The assertions are literal weights over the rows, never the sections.** A section that reads
/// `100` proves what the form draws and nothing about what **Save as done** writes — `T-18.12`'s
/// surviving probe was exactly that, a writer no test read. Each test here therefore ends on
/// ``SetEditorSections/rows`` or on the stored rows themselves.
@MainActor
@Suite("A group's load is its working sets'")
struct WarmupLoadTests {
    static let locale = Locale(identifier: "en_US_POSIX")

    // MARK: - What the form opens on (FR-18.6.8)

    @Test("A group led by a lighter warm-up opens on the working sets' load, not the warm-up's")
    func theFormReadsTheFirstWorkingSet() {
        let sections = Self.sections(Self.warmupThenWork)

        #expect(sections.sections.count == 1)
        #expect(sections.single.weightText == "100")
        #expect(sections.single.repsText == "5")
        // Every set of the group, the warm-up included: the rewrite is positional.
        #expect(sections.single.setsText == "4")
        // The form describes the work, so the switch is off — and the fold is open, because a
        // closed one reading *Sets 4* with the switch off would flatten the warm-up a second way.
        #expect(sections.single.isWarmup == false)
        #expect(sections.single.details.count == 4)
        #expect(sections.single.details.map(\.isWarmup) == [true, false, false, false])
    }

    @Test("DOD-18.13, at the sheet: saving that group untouched writes back what was stored")
    func anUntouchedSaveKeepsTheWarmupsLoad() {
        let rows = Self.sections(Self.warmupThenWork).rows

        #expect(rows.map(\.weight.grams) == [40_000, 100_000, 100_000, 100_000])
        #expect(rows.map(\.reps) == [8, 5, 5, 5])
        #expect(rows.map(\.isWarmup) == [true, false, false, false])
    }

    @Test("Editing the group's load moves the working sets and leaves the stored warm-up")
    func editingTheLoadLeavesAStoredWarmupAlone() {
        // `Q-18.11` (b). The field above the fold is the group's working load; the warm-up was
        // stored at one the form never said, so the edit is not about it.
        var sections = Self.sections(Self.warmupThenWork)
        var draft = sections.single
        draft.weightText = "102.5"
        sections.replace(draft, at: 0)

        #expect(sections.rows.map(\.weight.grams) == [40_000, 102_500, 102_500, 102_500])
    }

    @Test("A warm-up stored at the group's own load still follows the edit")
    func aWarmupAtTheGroupsLoadFollowsTheEdit() {
        // `Q-18.11` (b)'s other half, and it is every warm-up this sheet has ever written: the
        // fold has no load of its own, so a set marked warm-up here was stored at the group's.
        // The reps differ, which is what opens the fold at all.
        var sections = Self.sections(
            Self.oneSet(grams: 100_000, reps: 8, order: 0, isWarmup: true)
                + Self.run(grams: 100_000, reps: 5, count: 3, from: 1))
        #expect(sections.single.details.count == 4)
        var draft = sections.single
        draft.weightText = "102.5"
        sections.replace(draft, at: 0)

        #expect(sections.rows.map(\.weight.grams) == [102_500, 102_500, 102_500, 102_500])
    }

    @Test("A warm-up between two groups keeps its load and its position")
    func aWarmupBetweenGroupsKeepsItsLoad() {
        // It belongs to the group open where it sits, so the partition stays contiguous and the
        // positional rewrite shifts nothing: three rows, in the order they are stored in.
        let sections = Self.sections(
            Self.run(grams: 57_500, reps: 10, count: 1, from: 0)
                + Self.oneSet(grams: 20_000, reps: 10, order: 1, isWarmup: true)
                + Self.run(grams: 100_000, reps: 7, count: 1, from: 2))

        #expect(sections.sections.count == 2)
        #expect(sections.sections[0].draft.weightText == "57.5")
        #expect(sections.sections[1].draft.weightText == "100")
        #expect(sections.rows.map(\.weight.grams) == [57_500, 20_000, 100_000])
        #expect(sections.rows.map(\.isWarmup) == [false, true, false])
    }

    @Test("A group of warm-ups only opens on the first set's load, and each one keeps its own")
    func aGroupOfWarmupsOnlyOpensOnTheFirst() {
        // There is no working set to read, so the fallback is the first — and the ramp's later
        // rungs are exactly the sets nothing else here tells apart, which is why `isUniform`
        // compares the load.
        let sections = Self.sections(
            Self.oneSet(grams: 20_000, reps: 5, order: 0, isWarmup: true)
                + Self.oneSet(grams: 40_000, reps: 5, order: 1, isWarmup: true)
                + Self.oneSet(grams: 60_000, reps: 5, order: 2, isWarmup: true))

        #expect(sections.single.weightText == "20")
        #expect(sections.single.isWarmup == true)
        #expect(sections.rows.map(\.weight.grams) == [20_000, 40_000, 60_000])
    }

    @Test("A warm-up marked in the sheet takes the group's load, as it always has")
    func aWarmupAddedInTheSheetTakesTheGroupsLoad() {
        var sections = Self.sections(Self.run(grams: 100_000, reps: 5, count: 3, from: 0))
        // A uniform group opens with the fold closed.
        #expect(sections.single.details.isEmpty)
        var draft = sections.single.openingDetails()
        draft.details[0].isWarmup = true
        sections.replace(draft, at: 0)

        #expect(sections.rows.map(\.weight.grams) == [100_000, 100_000, 100_000])
        #expect(sections.rows.map(\.isWarmup) == [true, false, false])
    }

    @Test("The free workout's single form writes the load it says")
    func theSingleFormIsUntouched() {
        // `OUT-18.6`: that form has no stored group behind it, so no entry of its fold can carry a
        // load and every row takes the field's.
        var draft = SetDraft(unit: .kilograms, locale: Self.locale)
        draft.weightText = "60"
        draft.repsText = "5"
        draft.setsText = "2"
        draft.isWarmup = true

        let sections = SetEditorSections(single: draft)

        #expect(sections.rows.map(\.weight.grams) == [60_000, 60_000])
        #expect(sections.rows.allSatisfy { $0.isWarmup })
    }

    // MARK: - DOD-18.13, from History (FR-17.7.5, FR-16.4)

    @Test("A past session's warm-up survives a reopen and an untouched save")
    func aPastSessionSavedUntouchedStoresWhatItStored() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.logSet(at: 0, order: 0, weight: Weight(grams: 40_000), reps: 8, isWarmup: true)
        for order in 1..<4 {
            try await past.logSet(at: 0, order: order, weight: Weight(grams: 100_000), reps: 5)
        }
        try await past.markDone(at: 0)
        await past.state.load()
        let rowID = past.state.dayRows[0].id
        let sections = SetEditorSections(
            answering: try #require(past.state.editorRow(forRow: rowID)),
            unit: .kilograms,
            locale: Self.locale)
        let identifiers = try await past.storedSets(at: 0).sorted { $0.order < $1.order }.map(\.id)

        await past.state.log(rowID: rowID, rows: sections.rows)

        let stored = try await past.storedSets(at: 0)
            .filter { $0.deletedAt == nil }
            .sorted { $0.order < $1.order }
        #expect(past.state.writeFailure == nil)
        #expect(stored.map(\.weight.grams) == [40_000, 100_000, 100_000, 100_000])
        #expect(stored.map(\.reps) == [8, 5, 5, 5])
        #expect(stored.map(\.isWarmup) == [true, false, false, false])
        // Rewritten where they sat, so the same four rows rather than four new ones.
        #expect(stored.map(\.id) == identifiers)
    }

    @Test("The same group with the load corrected: the working sets move, the warm-up does not")
    func aPastSessionsLoadEditLeavesTheWarmup() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.logSet(at: 0, order: 0, weight: Weight(grams: 40_000), reps: 8, isWarmup: true)
        for order in 1..<4 {
            try await past.logSet(at: 0, order: order, weight: Weight(grams: 100_000), reps: 5)
        }
        try await past.markDone(at: 0)
        await past.state.load()
        let rowID = past.state.dayRows[0].id
        var sections = SetEditorSections(
            answering: try #require(past.state.editorRow(forRow: rowID)),
            unit: .kilograms,
            locale: Self.locale)
        var draft = sections.single
        draft.weightText = "102.5"
        sections.replace(draft, at: 0)

        await past.state.log(rowID: rowID, rows: sections.rows)

        let stored = try await past.storedSets(at: 0)
            .filter { $0.deletedAt == nil }
            .sorted { $0.order < $1.order }
        #expect(stored.map(\.weight.grams) == [40_000, 102_500, 102_500, 102_500])
    }

    // MARK: - What the app's own Log path wrote (G-2.4)

    @Test("A row logged from the day, reopened and saved untouched, writes nothing at all")
    func theDayPathRoundTripsWithoutAWrite() async throws {
        // `G-2.4`: the rewrite skips a member that resolves to what is stored, so an untouched
        // save leaves every `updatedAt` where it was. A prefill that read the warm-up's load would
        // resolve the three working sets to 40 kg and write all three.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await fixture.setTarget(day: 0, slot: 0, grams: 100_000, reps: 5, sets: 3)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let rowID = try #require(day.rows.first).id
        await day.log(
            rowID: rowID,
            rows: [Self.values(grams: 40_000, reps: 8, isWarmup: true)]
                + Array(repeating: Self.values(grams: 100_000, reps: 5, isWarmup: false), count: 3))
        let entryID = try await fixture.firstEntryID(day: 0)
        let before = try await Self.storedSets(fixture, entryID: entryID)
        try #require(before.map(\.weight.grams) == [40_000, 100_000, 100_000, 100_000])

        let reopened = SetEditorSections(
            answering: try #require(day.editorRow(forRow: entryID)),
            unit: .kilograms,
            locale: Self.locale)
        #expect(reopened.sections.count == 1)
        #expect(reopened.single.weightText == "100")
        await day.log(rowID: entryID, rows: reopened.rows)

        let after = try await Self.storedSets(fixture, entryID: entryID)
        #expect(after.map(\.weight.grams) == [40_000, 100_000, 100_000, 100_000])
        #expect(after.map(\.updatedAt) == before.map(\.updatedAt))
    }

    // MARK: - Fixtures

    /// One entry, because ``DerivedValues/SetGrouping`` refuses to join sets from two.
    static let entryID = UUID()

    /// `DOD-18.13`'s own group: `40 kg × 8` warm-up, then `100 kg × 5 × 3`.
    static var warmupThenWork: [SetEntry] {
        oneSet(grams: 40_000, reps: 8, order: 0, isWarmup: true)
            + run(grams: 100_000, reps: 5, count: 3, from: 1)
    }

    static func sections(_ logged: [SetEntry]) -> SetEditorSections {
        SetEditorSections(
            answering: SetEditorRow(plan: [], logged: logged),
            unit: .kilograms,
            locale: Self.locale)
    }

    static func run(grams: Int, reps: Int, count: Int, from seed: Int) -> [SetEntry] {
        (0..<count).flatMap { oneSet(grams: grams, reps: reps, order: seed + $0) }
    }

    static func oneSet(grams: Int, reps: Int, order: Int, isWarmup: Bool = false) -> [SetEntry] {
        [
            SetEntry(
                id: UUID(),
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                entryID: Self.entryID,
                order: order,
                weight: Weight(grams: grams),
                reps: reps,
                rpe: nil,
                rir: nil,
                isWarmup: isWarmup,
                isCompleted: true,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: .distantPast)
        ]
    }

    static func values(grams: Int, reps: Int, isWarmup: Bool) -> SetEntryValues {
        SetEntryValues(weight: Weight(grams: grams), reps: reps, rpe: nil, isWarmup: isWarmup)
    }

    static func storedSets(_ fixture: WeekFixture, entryID: UUID) async throws -> [SetEntry] {
        try await fixture.stack.workouts
            .sets(forEntryID: entryID, includingDeleted: false)
            .sorted { $0.order < $1.order }
    }
}
