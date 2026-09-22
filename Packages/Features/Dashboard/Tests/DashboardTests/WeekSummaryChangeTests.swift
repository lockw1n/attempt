import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-18.9.2`'s two lines and `FR-18.9.3`'s change: measured between the last two completed weeks,
/// never against the one in progress, and absent wherever one side has no volume.
///
/// The helpers — the Monday-first GMT calendar, the pinned "now", the empty weeks — are
/// ``WeekSummaryStateTests``', and every total is a hand-computed literal for that suite's reason.
@MainActor
@Suite("Week summary — two weeks and the change")
struct WeekSummaryChangeTests {

    @Test("A Monday with nothing logged draws last week, and its change against the week before")
    func mondayWithNothingThisWeek() async throws {
        // DOD-18.11's first half, and F-17's Monday: the card used to become an empty state here.
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        // Last week: 500 + 360. The week before: 500. The change is +360, and only a comparison
        // between those two produces it — this week is empty, so a comparison against it is nil.
        try await fixture.session(
            on: weeksAgo(1),
            exercises: [
                (squat, [LoggedSet(grams: 100_000, reps: 5), LoggedSet(grams: 120_000, reps: 3)])
            ])
        try await fixture.session(
            on: weeksAgo(2), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = WeekSummaryStateTests.state(fixture, now: WeekSummaryStateTests.monday)

        await state.load()

        let weeks = try #require(state.weeks)
        #expect(weeks.thisWeek == .empty)
        #expect(weeks.lastWeek == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 860_000)))
        #expect(weeks.weekBefore == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000)))
        #expect(weeks.lastWeekChange == Weight(grams: 360_000))
        #expect(WeekSummaryScreenState.current(state) == .ready(weeks))
        let lines = WeekLines(weeks)
        #expect(lines.thisWeek.reading == .quiet)
        #expect(lines.thisWeek.change == nil)
        #expect(lines.lastWeek.reading == .weighed(workouts: 1, tonnage: Weight(grams: 860_000)))
        #expect(lines.lastWeek.change == Weight(grams: 360_000))
    }

    @Test("Mid-week, this week's line carries no change, and last week's is against the week before")
    func midWeekCarriesNoChangeOnThisWeek() async throws {
        // DOD-18.11's second half. This week 400, last week 860, the week before 500: the one
        // right answer is +360 on last week's line. Comparing last week with THIS week would read
        // 460 either way round, and putting anything on this week's line is the part-week reading
        // FR-18.9.3 rules out — so both the value and the line are asserted by name.
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow, exercises: [(squat, [LoggedSet(grams: 80_000, reps: 5)])])
        try await fixture.session(
            on: weeksAgo(1),
            exercises: [
                (squat, [LoggedSet(grams: 100_000, reps: 5), LoggedSet(grams: 120_000, reps: 3)])
            ])
        try await fixture.session(
            on: weeksAgo(2), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = WeekSummaryStateTests.state(fixture)

        await state.load()

        let weeks = try #require(state.weeks)
        #expect(weeks.thisWeek == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 400_000)))
        #expect(weeks.lastWeekChange == Weight(grams: 360_000))
        let lines = WeekLines(weeks)
        #expect(lines.thisWeek.name == .thisWeek)
        #expect(lines.thisWeek.change == nil, "this week carries no change until it is over")
        #expect(lines.lastWeek.name == .lastWeek)
        #expect(lines.lastWeek.change == Weight(grams: 360_000))
    }

    @Test("With no volume in the week before last, last week has nothing to be compared with")
    func noChangeWithoutAWeekBefore() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: weeksAgo(1), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = WeekSummaryStateTests.state(fixture)

        await state.load()

        // Not +500: a change against nothing would report the whole of last week as a gain.
        let weeks = try #require(state.weeks)
        #expect(weeks.lastWeek == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000)))
        #expect(weeks.lastWeekChange == nil)
        #expect(WeekLines(weeks).lastWeek.change == nil)
        #expect(WeekLines(weeks).lastWeek.reading == .weighed(workouts: 1, tonnage: Weight(grams: 500_000)))
    }

    @Test("An empty last week says so and carries no change, whatever the week before held")
    func lastWeekEmptyCarriesNoChange() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow, exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        try await fixture.session(
            on: weeksAgo(2), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = WeekSummaryStateTests.state(fixture)

        await state.load()

        // Not −500: last week's absence is not a loss of everything. And not the empty state: two
        // of the three weeks hold training, so the card draws its lines and this one reads quiet.
        let weeks = try #require(state.weeks)
        #expect(weeks.lastWeek == .empty)
        #expect(weeks.lastWeekChange == nil)
        #expect(WeekSummaryScreenState.current(state) == .ready(weeks))
        #expect(WeekLines(weeks).lastWeek.reading == .quiet)
        #expect(WeekLines(weeks).lastWeek.change == nil)
    }

    @Test("Three empty weeks are the empty state, however much older history there is")
    func threeEmptyWeeksAreTheEmptyState() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        // A month off: trained four weeks ago, nothing since. Outside the three weeks, so it is
        // weighed into none of them.
        try await fixture.session(
            on: weeksAgo(4), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = WeekSummaryStateTests.state(fixture)

        await state.load()

        #expect(state.hasEverTrained)
        #expect(state.weeks == WeekSummaryStateTests.nothing)
        #expect(WeekSummaryScreenState.current(state) == .quiet)
        #expect(DashboardScreenState.current(state) == .sections)
    }

    @Test("A Sunday is this week under a Sunday-first calendar and last week under a Monday-first one")
    func firstWeekdayDecidesWhereSundayGoes() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        // Sunday 12 November 2023, noon UTC — two days before `fixtureNow`.
        try await fixture.session(
            on: Date(timeIntervalSince1970: 1_699_790_400),
            exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let trained = WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000))

        let mondayFirst = WeekSummaryStateTests.state(fixture, firstWeekday: 2)
        await mondayFirst.load()
        #expect(mondayFirst.weeks?.thisWeek == .empty)
        #expect(mondayFirst.weeks?.lastWeek == trained)

        let sundayFirst = WeekSummaryStateTests.state(fixture, firstWeekday: 1)
        await sundayFirst.load()
        #expect(sundayFirst.weeks?.thisWeek == trained)
        #expect(sundayFirst.weeks?.lastWeek == .empty)
    }

    @Test("A week runs from the first instant of its first day to the last of its last, and no session is in two")
    func weekEdges() async throws {
        // Monday-first around `fixtureNow`: this week is 13–19 November 2023, last week 6–12, the
        // week before 30 October–5 November, all UTC. Seven sessions, each one second inside or
        // outside an edge, each with a distinct total so that a session landing in the wrong week
        // — or in two — moves a number.
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        let sessions: [(TimeInterval, LoggedSet)] = [
            (1_700_438_399, LoggedSet(grams: 100_000, reps: 5)),  // Sun 19 Nov 23:59:59 — this week, 500
            (1_699_833_600, LoggedSet(grams: 120_000, reps: 3)),  // Mon 13 Nov 00:00:00 — this week, 360
            (1_699_833_599, LoggedSet(grams: 80_000, reps: 5)),  // Sun 12 Nov 23:59:59 — last week, 400
            (1_699_228_800, LoggedSet(grams: 100_000, reps: 2)),  // Mon 6 Nov 00:00:00 — last week, 200
            (1_698_624_000, LoggedSet(grams: 100_000, reps: 1)),  // Mon 30 Oct 00:00:00 — the week before, 100
            (1_698_623_999, LoggedSet(grams: 150_000, reps: 1)),  // Sun 29 Oct 23:59:59 — outside, 150
            (1_700_438_400, LoggedSet(grams: 200_000, reps: 1)),  // Mon 20 Nov 00:00:00 — next week, 200
        ]
        for (instant, set) in sessions {
            try await fixture.session(
                on: Date(timeIntervalSince1970: instant), exercises: [(squat, [set])])
        }
        let state = WeekSummaryStateTests.state(fixture)

        await state.load()

        #expect(
            state.weeks
                == WeekSummaries(
                    thisWeek: WeekSummary(workoutCount: 2, tonnage: Weight(grams: 860_000)),
                    lastWeek: WeekSummary(workoutCount: 2, tonnage: Weight(grams: 600_000)),
                    weekBefore: WeekSummary(workoutCount: 1, tonnage: Weight(grams: 100_000))))
    }

    @Test("Two equal weeks are a change of zero, drawn flat, not a missing one")
    func equalWeeksAreAChangeOfZero() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: weeksAgo(1), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        try await fixture.session(
            on: weeksAgo(2), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = WeekSummaryStateTests.state(fixture)

        await state.load()

        // There was something to compare, and it did not move — the tiles' own rule for a zero.
        let change = try #require(state.weeks?.lastWeekChange)
        #expect(change == .zero)
        #expect(WeekLine.direction(of: change) == .unchanged)
    }

    @Test("A falling week is a negative change, drawn as a decrease")
    func aFallingWeek() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: weeksAgo(1), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        try await fixture.session(
            on: weeksAgo(2),
            exercises: [
                (squat, [LoggedSet(grams: 100_000, reps: 5), LoggedSet(grams: 120_000, reps: 3)])
            ])
        let state = WeekSummaryStateTests.state(fixture)

        await state.load()

        // 500 − 860.
        let change = try #require(state.weeks?.lastWeekChange)
        #expect(change == Weight(grams: -360_000))
        #expect(WeekLine.direction(of: change) == .decrease)
        #expect(WeekLine.direction(of: Weight(grams: 360_000)) == .increase)
    }

    @Test("A week of bodyweight work on either side of the comparison leaves no change")
    func anUnweighedWeekCarriesNoChange() async throws {
        let bodyweight = [LoggedSet(grams: 0, reps: 10), LoggedSet(grams: -20_000, reps: 8)]

        // Last week unweighed, the week before weighed: not −500.
        let lastUnweighed = DashboardFixture()
        let pullUp = try await lastUnweighed.exercise(named: "Pull-Up")
        let squat = try await lastUnweighed.exercise(named: "Back Squat")
        try await lastUnweighed.session(on: weeksAgo(1), exercises: [(pullUp, bodyweight)])
        try await lastUnweighed.session(
            on: weeksAgo(2), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let first = WeekSummaryStateTests.state(lastUnweighed)
        await first.load()
        let firstWeeks = try #require(first.weeks)
        #expect(firstWeeks.lastWeek == WeekSummary(workoutCount: 1, tonnage: .zero))
        #expect(firstWeeks.lastWeekChange == nil)
        #expect(WeekLines(firstWeeks).lastWeek.reading == .unweighed(workouts: 1))
        #expect(WeekLines(firstWeeks).lastWeek.change == nil)

        // The week before unweighed, last week weighed: not +500.
        let beforeUnweighed = DashboardFixture()
        let pullUp2 = try await beforeUnweighed.exercise(named: "Pull-Up")
        let squat2 = try await beforeUnweighed.exercise(named: "Back Squat")
        try await beforeUnweighed.session(
            on: weeksAgo(1), exercises: [(squat2, [LoggedSet(grams: 100_000, reps: 5)])])
        try await beforeUnweighed.session(on: weeksAgo(2), exercises: [(pullUp2, bodyweight)])
        let second = WeekSummaryStateTests.state(beforeUnweighed)
        await second.load()
        #expect(second.weeks?.weekBefore == WeekSummary(workoutCount: 1, tonnage: .zero))
        #expect(second.weeks?.lastWeekChange == nil)
    }

    @Test("One session read, and the entries of only the three weeks' sessions")
    func onePassOverThreeWeeks() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        for weeks in [0, 1, 2, 4] {
            try await fixture.session(
                on: weeksAgo(weeks), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        }
        let observed = SwitchableWorkouts(wrapping: fixture.repositories.workouts)
        let state = WeekSummaryState(
            workouts: observed, calendar: WeekSummaryStateTests.calendar(), now: { fixtureNow })

        await state.load()

        // Three weeks from one unbounded read, not three bounded ones; and the session four weeks
        // back is never walked into — its entries are the difference between three and four.
        #expect(await observed.sessionReads == 1)
        #expect(await observed.entryReads == 3)
        #expect(state.weeks?.thisWeek.workoutCount == 1)
        #expect(state.weeks?.lastWeek.workoutCount == 1)
        #expect(state.weeks?.weekBefore.workoutCount == 1)
    }

    @Test("Training in the week before alone draws two quiet lines, not the empty state")
    func weekBeforeAloneIsNotTheEmptyState() async throws {
        // FR-18.9.2 keeps the empty state for one case only, and this is the one nearest to it: two
        // weeks off after a trained week. The empty state's sentence would say no set was logged in
        // the week before, which is false; the card draws its lines and each says quiet in words.
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: weeksAgo(2), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = WeekSummaryStateTests.state(fixture)

        await state.load()

        let weeks = try #require(state.weeks)
        #expect(weeks.weekBefore == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000)))
        #expect(!weeks.isQuiet)
        #expect(WeekSummaryScreenState.current(state) == .ready(weeks))
        #expect(WeekLines(weeks).thisWeek.reading == .quiet)
        #expect(WeekLines(weeks).lastWeek.reading == .quiet)
        #expect(WeekLines(weeks).lastWeek.change == nil)
    }

    @Test("Each line reads to VoiceOver as one sentence, in both catalogues")
    func eachLineIsOneSpokenSentence() {
        // G-4.2, and G-4.5 for the ear: four shapes of line, each one sentence with one full stop,
        // the direction said in a word where the eye gets an arrow and a sign. Every piece follows
        // the locale the line is given, so the Ukrainian sentence has no English noun inside it.
        let english = Locale(identifier: "en_US")
        let ukrainian = Locale(identifier: "uk")
        func spoken(_ model: WeekLineModel, _ locale: Locale) -> String {
            String(localized: WeekLine.spoken(for: model, unit: .kilograms, locale: locale))
        }
        let quiet = WeekLineModel(name: .thisWeek, reading: .quiet, change: nil)
        let unweighed = WeekLineModel(name: .lastWeek, reading: .unweighed(workouts: 3), change: nil)
        let figures = WeekLineModel(
            name: .thisWeek,
            reading: .weighed(workouts: 1, tonnage: Weight(grams: 4_200_000)),
            change: nil)
        let risen = WeekLineModel(
            name: .lastWeek,
            reading: .weighed(workouts: 3, tonnage: Weight(grams: 12_400_000)),
            change: Weight(grams: 100_000))
        let fallen = WeekLineModel(
            name: .lastWeek,
            reading: .weighed(workouts: 3, tonnage: Weight(grams: 12_400_000)),
            change: Weight(grams: -2_600_000))
        let flat = WeekLineModel(
            name: .lastWeek,
            reading: .weighed(workouts: 3, tonnage: Weight(grams: 12_400_000)),
            change: .zero)

        #expect(spoken(quiet, english) == "This week: No working sets yet.")
        #expect(
            spoken(unweighed, english)
                == "Last week: 3 workouts, No load to weigh — bodyweight and assisted sets add no volume.")
        #expect(spoken(figures, english) == "This week: 1 workout, 4,200 kg.")
        #expect(spoken(risen, english) == "Last week: 3 workouts, 12,400 kg, up 100 kg on the week before.")
        #expect(
            spoken(fallen, english)
                == "Last week: 3 workouts, 12,400 kg, down 2,600 kg on the week before.")
        #expect(
            spoken(flat, english) == "Last week: 3 workouts, 12,400 kg, the same as the week before.")

        let risenUkrainian = spoken(risen, ukrainian)
        #expect(risenUkrainian.hasPrefix("Минулий тиждень: 3 тренування, "))
        #expect(risenUkrainian.hasSuffix(" більше, ніж тижнем раніше."))
        #expect(spoken(unweighed, ukrainian).hasPrefix("Минулий тиждень: 3 тренування, Немає ваги"))
        #expect(spoken(quiet, ukrainian) == "Цей тиждень: Робочих підходів ще немає.")
        for model in [quiet, unweighed, figures, risen, fallen, flat] {
            for locale in [english, ukrainian] {
                let sentence = spoken(model, locale)
                #expect(sentence.hasSuffix("."), "\(sentence)")
                #expect(!sentence.contains(".."), "\(sentence)")
            }
        }
    }

}
