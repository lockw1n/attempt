import Foundation

/// This module's copy (`G-3.4`), and the only place a history string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` — or, for the one that
/// pluralises, in `Localizable.stringsdict` — and binds it to this module's own bundle. The key
/// convention is documented once, in `Localization`.
enum HistoryStrings {
    /// What there is none of, on a first launch (`FR-1.13.2`).
    static let emptyHeadline = resource("history.list.empty.headline")

    /// Where sessions come from, once there are any.
    static let emptyMessage = resource("history.list.empty.message")

    /// The way to make the first one — a tab away, so it is a button rather than a sentence.
    static let emptyAction = resource("history.list.empty.action")

    /// A failed read of the list.
    static let errorHeadline = resource("history.list.error.headline")

    /// What to do about it.
    static let errorMessage = resource("history.list.error.message")

    /// A failed read of the next page, reported under the rows that did load.
    static let moreErrorMessage = resource("history.list.more.error")

    /// A session that was finished with nothing logged into it.
    static let noExercises = resource("history.list.exercises.none")

    /// The way from the list to the month grid — a toolbar control drawn as a symbol, so this is
    /// the only thing that names it (`G-4.2`).
    static let listCalendar = resource("history.list.calendar")

    /// The search field's prompt (`FR-1.5.4`). The field is the system's, so this is the only thing
    /// that says what it searches.
    static let searchPrompt = resource("history.list.search.prompt")

    /// A failed read of the history a search walks.
    static let searchErrorHeadline = resource("history.list.search.error.headline")

    /// What to do about it.
    static let searchErrorMessage = resource("history.list.search.error.message")

    /// The heading when nothing in the history contains the query.
    static let noMatchesHeadline = resource("history.list.nomatches.headline")

    /// What to do about a search that matched nothing.
    static let noMatchesMessage = resource("history.list.nomatches.message")

    /// The way back out of it.
    static let noMatchesAction = resource("history.list.nomatches.action")

    /// Why a result row is in the results: the query names one of its exercises.
    static let matchExercise = resource("history.list.match.exercise")

    /// The query is in the session's own note (`FR-1.2.9`).
    static let matchSessionNote = resource("history.list.match.note")

    /// The query is in a note on one of its sets (`FR-1.2.3`) — the one match a row shows no other
    /// evidence of, which is why the note itself is drawn beneath this line.
    static let matchSetNote = resource("history.list.match.setnote")

    /// The month grid's own title (`FR-1.5.3`). A pushed screen names itself.
    static let calendarTitle = resource("history.calendar.title")

    /// The chevron back a month. A symbol, so the label is the whole of what VoiceOver gets.
    static let calendarEarlier = resource("history.calendar.earlier")

    /// The chevron on a month.
    static let calendarLater = resource("history.calendar.later")

    /// Nothing has ever been logged, so there is nothing to mark (`FR-1.13.2`).
    static let calendarEmptyHeadline = resource("history.calendar.empty.headline")

    /// What will appear here once there is.
    static let calendarEmptyMessage = resource("history.calendar.empty.message")

    /// The way to make the first one — a tab away, so it is a button rather than a sentence.
    static let calendarEmptyAction = resource("history.calendar.empty.action")

    /// A failed read of the sessions the grid marks.
    static let calendarErrorHeadline = resource("history.calendar.error.headline")

    /// What to do about it.
    static let calendarErrorMessage = resource("history.calendar.error.message")

    /// A failed read of one day's sessions, reported under the grid that is still correct.
    static let calendarDayError = resource("history.calendar.day.error")

    /// A grid cell's VoiceOver label for a day training was logged on.
    ///
    /// The cell shows one or two digits, so the date has to be spoken in full (`G-4.2`) — and the
    /// marker itself is a fill and a dot, neither of which VoiceOver reads. This sentence is the
    /// third of `G-4.5`'s non-colour signals rather than a decoration on the other two.
    ///
    /// - Parameter date: The day, already rendered — how a date reads is `AppFormat`'s.
    /// - Returns: The label.
    static func calendarDayTrained(date: String) -> LocalizedStringResource {
        resource("history.calendar.day.trained \(date)")
    }

    /// A grid cell's VoiceOver label for a day with nothing logged on it.
    ///
    /// - Parameter date: The day, already rendered.
    /// - Returns: The label.
    static func calendarDayUntrained(date: String) -> LocalizedStringResource {
        resource("history.calendar.day.untrained \(date)")
    }

    /// The row's two numbers as one line — "8 working sets, 7,240 kg".
    ///
    /// **The line is the copy and the accessibility label both.** A pair of labelled metric tiles
    /// reads out to VoiceOver as bare numerals and wraps its numeral across three lines at the
    /// largest Dynamic Type size; one sentence does neither. It says *working* because warmups are
    /// not in the count, and a label that did not say so would be wrong rather than terse.
    ///
    /// - Parameters:
    ///   - sets: How many working sets were performed. The plural agrees with this.
    ///   - volume: The tonnage, already rendered — how a weight reads is `AppFormat`'s, and a
    ///     catalogue cannot decide it.
    /// - Returns: The sentence.
    static func metricsSummary(sets: Int, volume: String) -> LocalizedStringResource {
        resource("history.list.metrics.summary \(sets) \(volume)")
    }

    /// Which week and day of a program a session was started from (`FR-16.8.3`, `DOD-16.1`).
    ///
    /// **A key of this module's own**, on the rule the two sentences above follow: a history row
    /// describes a workout that happened, and it is free to diverge from the line Train draws over
    /// a plan that has not.
    ///
    /// - Parameters:
    ///   - week: The week the session was started under.
    ///   - day: Its day's position, counting from one.
    /// - Returns: The line.
    static func programWeekAndDay(week: Int, day: Int) -> LocalizedStringResource {
        resource("history.list.program.week-day \(week) \(day)")
    }

    /// Every key this module can show, for the resolution test.
    ///
    /// The plural is included at one arbitrary count: what the test asks is whether the key resolves
    /// to copy, and a format that resolves at one count resolves at all of them.
    static var all: [LocalizedStringResource] {
        [
            emptyHeadline, emptyMessage, emptyAction,
            errorHeadline, errorMessage, moreErrorMessage,
            noExercises, listCalendar,
            searchPrompt, searchErrorHeadline, searchErrorMessage,
            noMatchesHeadline, noMatchesMessage, noMatchesAction,
            matchExercise, matchSessionNote, matchSetNote,
            calendarTitle, calendarEarlier, calendarLater,
            calendarEmptyHeadline, calendarEmptyMessage, calendarEmptyAction,
            calendarErrorHeadline, calendarErrorMessage, calendarDayError,
            calendarDayTrained(date: ""), calendarDayUntrained(date: ""),
            metricsSummary(sets: 1, volume: ""),
            programWeekAndDay(week: 2, day: 1),
        ]
    }

    /// Binds a key to this module's catalogue.
    private static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
