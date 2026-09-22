import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `DOD-18.3` and `FR-18.6.3`/`FR-18.6.7` end to end: a plan naming two groups, logged from the
/// sheet in one visit with a deviation in the **second**, and every reader of that answer.
///
/// **Every Phase 1.7 fixture used a one-group plan**, which is why `F-10` survived a phase of
/// tests: a sheet that writes only the first group is indistinguishable from a correct one when
/// there is only ever one. Each test here fails on a one-group plan for the right reason — it
/// cannot be written.
@MainActor
@Suite("A plan of two groups, answered")
struct MultiGroupSaveTests {
    static let locale = Locale(identifier: "en_US_POSIX")

    /// `DOD-18.3`'s own prescription: `57 × 10 × 3`, then `64 × 8 × 3`.
    static func planned(_ fixture: WeekFixture) async throws {
        try await fixture.setTarget(day: 0, slot: 0, grams: 57_000, reps: 10, sets: 3)
        try await fixture.addTarget(day: 0, slot: 0, grams: 64_000, reps: 8, sets: 3)
    }

    /// What the sheet resolves to when the lifter drops the back-offs to seven reps.
    static func answer(_ row: SetEditorRow) -> SetEditorSections {
        var sections = SetEditorSections(answering: row, unit: .kilograms, locale: Self.locale)
        var second = sections.sections[1].draft
        second.repsText = "7"
        sections.replace(second, at: 1)
        return sections
    }

    // MARK: - DOD-18.3, as one script

    @Test("One visit writes both groups, and the row, the past day and next week all read both")
    func theWholeExerciseIsLoggedInOneVisit() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await Self.planned(fixture)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        let rowID = try #require(day.rows.first).id
        // The sheet opens on the plan: two sections, the second prefilled 64 × 8 × 3.
        let sections = Self.answer(try #require(day.editorRow(forRow: rowID)))
        #expect(sections.sections.count == 2)

        await day.log(rowID: rowID, rows: sections.rows)

        // THE ROW (`FR-18.3.2`): its **Did** line lists both groups, the second as done.
        let row = try #require(day.rows.first)
        #expect(row.answer == .logged)
        #expect(row.performed.map { ($0.weight?.grams, $0.reps, $0.sets) }.count == 2)
        #expect(row.performed[0].weight == Weight(grams: 57_000))
        #expect(row.performed[0].reps == 10)
        #expect(row.performed[0].sets == 3)
        #expect(row.performed[1].weight == Weight(grams: 64_000))
        #expect(row.performed[1].reps == 7)
        #expect(row.performed[1].sets == 3)
        // Its **Planned** line still names both, untouched.
        #expect(row.plan.count == 2)

        // THE PAST DAY (`FR-17.7.5`): the same answer, read back off the stored session.
        let entryID = try await fixture.firstEntryID(day: 0)
        let stored = try await fixture.stack.workouts
            .sets(forEntryID: entryID, includingDeleted: false)
            .sorted { $0.order < $1.order }
        #expect(stored.count == 6)
        #expect(stored.allSatisfy { $0.isCompleted })
        #expect(SetGrouping.groups(stored, at: .loadAndReps).map(\.count) == [3, 3])

        // START NEXT WEEK (`FR-17.8.6`): the proposal copies the adjustment **per group**, so the
        // back-offs are carried at seven reps and the top set at ten. A rule that copied the first
        // group's adjustment to both is `F-10` one screen later.
        let proposed = SessionAsRoutine.targets(from: stored)
        #expect(proposed.map(\.reps) == [10, 7])
        #expect(proposed.map(\.sets) == [3, 3])
        #expect(proposed.map { $0.weight?.grams } == [57_000, 64_000])
    }

    @Test("NFR-18.1: a deviation in any group is one visit — open, change, save")
    func aDeviationIsOneVisit() async throws {
        // The tap count, recorded rather than assumed (`NFR-18.1`): **Log** opens the sheet
        // already holding both groups, the second section's Reps takes one `−`, and **Save as
        // done** stores both. Three taps, the same three `FR-17.1.7` counts for one group — the
        // sections cost none, because they open prefilled.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await Self.planned(fixture)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let rowID = try #require(day.rows.first).id

        // Tap 1: **Log**.
        var sections = SetEditorSections(
            answering: try #require(day.editorRow(forRow: rowID)),
            unit: .kilograms,
            locale: Self.locale)
        // Tap 2: one `−` on the second section's Reps.
        sections.replace(sections.sections[1].draft.adjustingReps(by: -1), at: 1)
        // Tap 3: **Save as done**.
        await day.log(rowID: rowID, rows: sections.rows)

        let row = try #require(day.rows.first)
        #expect(row.performed.map(\.reps) == [10, 7])
        #expect(row.answer == .logged)
    }

    // MARK: - One chained command (FR-18.6.3, NFR-18.3)

    @Test("One save is one command: every set it writes carries the same moment")
    func oneSaveIsOneCommand() async throws {
        // A chain is unobservable from its result, so this asserts the thing that would move if
        // the view looped the single-group command once per section: `writeLoggedGroup` takes one
        // `Date.now` and stamps every row with it. N commands are N moments, and N reloads.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await Self.planned(fixture)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let rowID = try #require(day.rows.first).id
        let sections = Self.answer(try #require(day.editorRow(forRow: rowID)))

        await day.log(rowID: rowID, rows: sections.rows)

        let stored = try await fixture.stack.workouts
            .sets(forEntryID: try await fixture.firstEntryID(day: 0), includingDeleted: false)
        let moments = Set(stored.compactMap(\.completedAt))
        #expect(stored.count == 6)
        #expect(moments.count == 1)
        #expect(Set(stored.map(\.createdAt)).count == 1)
    }

    // MARK: - The rewrite (FR-17.7.5)

    @Test("Reopening an answered two-group row rewrites every group, not the first")
    func theRewriteReachesEveryGroup() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await Self.planned(fixture)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let rowID = try #require(day.rows.first).id
        await day.log(
            rowID: rowID, rows: Self.answer(try #require(day.editorRow(forRow: rowID))).rows)
        let entryID = try await fixture.firstEntryID(day: 0)
        try #require(day.rows.first?.performed.map(\.reps) == [10, 7])

        // Reopened: both sections read what is stored, and the *second* is corrected again.
        var reopened = SetEditorSections(
            answering: try #require(day.editorRow(forRow: entryID)),
            unit: .kilograms,
            locale: Self.locale)
        #expect(reopened.sections.count == 2)
        #expect(reopened.sections[1].draft.repsText == "7")
        var second = reopened.sections[1].draft
        second.repsText = "6"
        reopened.replace(second, at: 1)

        await day.log(rowID: entryID, rows: reopened.rows)

        let row = try #require(day.rows.first)
        #expect(row.performed.map(\.reps) == [10, 6])
        // Rewritten where they sat rather than appended to: six sets, not twelve.
        #expect(row.loggedSetCount == 6)
    }

    @Test("More logged groups than the plan names: Save writes them all back, none dropped")
    func anUnplannedGroupSurvivesTheSave() async throws {
        // The rewrite is positional (``SetGroupRewrite``: `stored.dropFirst(rows.count)` is
        // deleted), so a group left out of `rows` is one **Save as done** removes. A row can hold
        // more groups than the plan names — one rewritten before this task existed, or an imported
        // session (`FR-16.4`) — and reopening it must not cost the lifter the unplanned group.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await fixture.setTarget(day: 0, slot: 0, grams: 57_000, reps: 10, sets: 3)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let rowID = try #require(day.rows.first).id
        // Answered with two groups against a plan naming one.
        await day.log(
            rowID: rowID,
            rows: .of(grams: 57_000, reps: 10, sets: 3) + .of(grams: 64_000, reps: 7, sets: 3))
        let entryID = try await fixture.firstEntryID(day: 0)
        try #require(day.rows.first?.performed.count == 2)

        // Reopened: one planned section, one the plan does not name, and Save writes both.
        let reopened = SetEditorSections(
            answering: try #require(day.editorRow(forRow: entryID)),
            unit: .kilograms,
            locale: Self.locale)
        #expect(reopened.sections.count == 2)
        #expect(reopened.sections[1].plan.isEmpty)
        #expect(reopened.rows.count == 6)

        await day.log(rowID: entryID, rows: reopened.rows)

        let row = try #require(day.rows.first)
        #expect(row.performed.map { $0.weight?.grams } == [57_000, 64_000])
        #expect(row.loggedSetCount == 6)
    }

    @Test("Zeroing a section on an answered row removes that group's sets rather than leaving them")
    func zeroingASectionOnARewriteRemovesItsSets() async throws {
        // `aZeroSectionWritesNoRow` covers the append; this is the rewrite, where three rows
        // against six stored is a deletion rather than a gap.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await Self.planned(fixture)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let rowID = try #require(day.rows.first).id
        await day.log(
            rowID: rowID, rows: Self.answer(try #require(day.editorRow(forRow: rowID))).rows)
        let entryID = try await fixture.firstEntryID(day: 0)
        try #require(day.rows.first?.loggedSetCount == 6)

        var reopened = SetEditorSections(
            answering: try #require(day.editorRow(forRow: entryID)),
            unit: .kilograms,
            locale: Self.locale)
        var second = reopened.sections[1].draft
        second.setsText = "0"
        reopened.replace(second, at: 1)
        #expect(reopened.rows.count == 3)

        await day.log(rowID: entryID, rows: reopened.rows)

        let row = try #require(day.rows.first)
        #expect(row.performed.count == 1)
        #expect(row.performed[0].weight == Weight(grams: 57_000))
        #expect(row.loggedSetCount == 3)
        #expect(row.answer == .logged)
    }

    @Test("A section at zero sets writes nothing, and the row reads one group")
    func aZeroSectionWritesNoRow() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await Self.planned(fixture)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let rowID = try #require(day.rows.first).id
        var sections = SetEditorSections(
            answering: try #require(day.editorRow(forRow: rowID)),
            unit: .kilograms,
            locale: Self.locale)
        var second = sections.sections[1].draft
        second.setsText = "0"
        sections.replace(second, at: 1)

        await day.log(rowID: rowID, rows: sections.rows)

        let row = try #require(day.rows.first)
        #expect(row.answer == .logged)
        #expect(row.performed.count == 1)
        #expect(row.loggedSetCount == 3)
        // The plan still names both — the sheet never edits it (`FR-15.3.5`).
        #expect(row.plan.count == 2)
    }

    // MARK: - The plan is never touched (FR-15.3.5)

    @Test("Saving every section leaves the routine and this week's targets exactly as they were")
    func theSheetNeverTouchesThePlan() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await Self.planned(fixture)
        let day = fixture.dayStore(dayIndex: 0)
        await day.load()
        let rowID = try #require(day.rows.first).id
        let before = try await fixture.prescription(ofRoutineID: fixture.routineIDs[0])
        #expect(before.count == 2)

        await day.log(
            rowID: rowID, rows: Self.answer(try #require(day.editorRow(forRow: rowID))).rows)

        // The routine's own rows, group for group.
        let after = try await fixture.prescription(ofRoutineID: fixture.routineIDs[0])
        #expect(after == before)
        // And the week's targets, which are what the Planned line is drawn from.
        #expect(day.rows.first?.plan.map(\.reps) == [10, 8])
        #expect(day.rows.first?.plan.map(\.sets) == [3, 3])
    }

    // MARK: - Record badges (FR-1.6.1, FR-18.6.7)

    @Test("Each group that set a record gets its own badge")
    func everyGroupCarriesItsOwnRecord() async throws {
        // `FR-18.6.7`'s last reader. The two groups stand at different cells — three at 57 × 10
        // and three at 64 × 7 — so a save that wrote only the first would leave the heavier
        // group's cells empty, which is the shape the row's badges are read from.
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await Self.planned(fixture)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        let rowID = try #require(day.rows.first).id

        await day.log(
            rowID: rowID, rows: Self.answer(try #require(day.editorRow(forRow: rowID))).rows)

        await store.settleRecordRefresh()
        let stored = try await fixture.stack.workouts
            .sets(forEntryID: try await fixture.firstEntryID(day: 0), includingDeleted: false)
            .sorted { $0.order < $1.order }
        let groups = SetGrouping.groups(stored, at: .loadAndReps)
        #expect(groups.count == 2)
        for group in groups {
            let marked = group.sets.contains { !store.personalRecords.marks(forSetID: $0.id).isEmpty }
            #expect(marked)
        }
    }

    // MARK: - The past day (FR-17.7.5)

    @Test("A past day's two-group answer reopens on two sections and rewrites both")
    func aPastDayRewritesEveryGroup() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.plan(at: 0, order: 0, weight: Weight(grams: 57_000), reps: 10, sets: 3)
        try await past.plan(at: 0, order: 1, weight: Weight(grams: 64_000), reps: 8, sets: 3)
        for order in 0..<3 {
            try await past.logSet(at: 0, order: order, weight: Weight(grams: 57_000), reps: 10)
        }
        for order in 3..<6 {
            try await past.logSet(at: 0, order: order, weight: Weight(grams: 64_000), reps: 7)
        }
        try await past.markDone(at: 0)
        await past.state.load()
        let rowID = past.state.dayRows[0].id

        var sections = SetEditorSections(
            answering: try #require(past.state.editorRow(forRow: rowID)),
            unit: .kilograms,
            locale: Self.locale)
        #expect(sections.sections.count == 2)
        #expect(sections.sections[1].draft.repsText == "7")
        var second = sections.sections[1].draft
        second.repsText = "6"
        sections.replace(second, at: 1)

        await past.state.log(rowID: rowID, rows: sections.rows)

        let stored = try await past.storedSets(at: 0)
            .filter { $0.deletedAt == nil }
            .sorted { $0.order < $1.order }
        #expect(stored.count == 6)
        #expect(stored.prefix(3).allSatisfy { $0.reps == 10 })
        #expect(stored.suffix(3).allSatisfy { $0.reps == 6 })
        #expect(past.state.writeFailure == nil)
        // The plan is untouched, both groups of it (`FR-15.3.5`).
        #expect(past.state.exercises[0].planned.map(\.targetReps) == [10, 8])
    }

    // MARK: - Adherence (FR-15.3.3)

    @Test("Adherence counts the group that was done and the one that was not, separately")
    func adherenceReadsEveryGroup() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 1)
        try await Self.planned(fixture)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        let rowID = try #require(day.rows.first).id
        var sections = SetEditorSections(
            answering: try #require(day.editorRow(forRow: rowID)),
            unit: .kilograms,
            locale: Self.locale)
        var second = sections.sections[1].draft
        second.setsText = "0"
        sections.replace(second, at: 1)

        await day.log(rowID: rowID, rows: sections.rows)

        let adherence = try #require(SessionAdherence(store.exercises))
        // Six prescribed across the two groups; the three that were done are on target and the
        // three that were not are missing rather than wrong.
        #expect(adherence.prescribed == 6)
        #expect(adherence.asPrescribed == 3)
    }
}
