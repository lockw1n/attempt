import Foundation
import PowerliftingCore
import RepositoryInterface

/// The training log flattened to one row per set — `FR-1.11.1`'s CSV half.
///
/// **A machine format, so its headings and its enumerations are stable English and its numbers are
/// locale-independent.** That is not an oversight of `G-3.4`: a comma-separated file written in a
/// comma-decimal locale is a file whose own separator appears inside its fields, and a heading that
/// changed with the reader's language is a heading no formula can reference. The lifter's own words
/// — every note, every modifier they typed — are carried verbatim.
///
/// **The exercise column is the English name, whatever locale the export was taken in**
/// (`FR-1.14.2` resolves what a *screen* shows). Same argument as the headings: two exports of one
/// log must line up, and a column whose values changed with the exporter's language is a column no
/// sheet can join on. Nothing is lost — the Ukrainian name is a field of the exercise in
/// ``TrainingLogArchive``'s JSON, which is `FR-1.11.1`'s lossless half.
///
/// **This is the readable half rather than the lossless one.** `FR-1.11.1` names two formats and
/// gives "lossless" to the JSON; a weight is written in the unit the lifter reads in, rounded to the
/// third decimal, and the exact grams are ``TrainingLogArchive``'s.
enum TrainingLogCSV {
    /// The columns, in order. The first row of every file.
    ///
    /// - Parameter unit: The unit the weight column is written in — it is named in the heading, so a
    ///   file cannot be read in the wrong one.
    /// - Returns: The heading row's fields.
    static func headings(for unit: MassUnit) -> [String] {
        [
            "date", "session_notes", "exercise", "exercise_notes", "set_number",
            "weight_\(symbol(for: unit))", "reps", "rpe", "rir", "set_type", "outcome",
            "modifiers", "set_notes",
        ]
    }

    /// Renders the whole log.
    ///
    /// Rows are the chronological order the app reads sets in: session date, then session id, then
    /// the entry's position in the session, then the set's position in the entry.
    ///
    /// - Parameters:
    ///   - archive: The log to flatten.
    ///   - unit: The unit to write weights in.
    ///   - timeZone: The zone the session day is read back in. A session's date is the training
    ///     *day*, stored as that day's start in the calendar it was logged in, so a fixed zone here
    ///     would move a late-evening workout onto the previous or the next date.
    /// - Returns: The file's text, CRLF-terminated per RFC 4180.
    static func render(
        _ archive: TrainingLogArchive, unit: MassUnit, timeZone: TimeZone = .current
    ) -> String {
        let names = Dictionary(
            archive.exercises.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        let entriesBySession = Dictionary(grouping: archive.entries, by: \.sessionID)
        let setsByEntry = Dictionary(grouping: archive.sets, by: \.entryID)
        let day = dayFormatter(timeZone)

        var rows = [row(headings(for: unit))]
        for session in archive.sessions.sorted(by: chronological) {
            for entry in (entriesBySession[session.id] ?? []).sorted(by: { $0.order < $1.order }) {
                for set in (setsByEntry[entry.id] ?? []).sorted(by: { $0.order < $1.order }) {
                    let line = Line(
                        session: session,
                        entry: entry,
                        set: set,
                        exercise: names[entry.exerciseID])
                    rows.append(row(fields(line, unit: unit, day: day)))
                }
            }
        }
        return rows.joined()
    }

    /// One set with the rows above it — which is what a line of a flat file actually is.
    private struct Line {
        let session: WorkoutSession
        let entry: ExerciseEntry
        let set: SetEntry
        let exercise: Exercise?
    }

    /// One line's fields, in ``headings(for:)``' order.
    private static func fields(_ line: Line, unit: MassUnit, day: DateFormatter) -> [String] {
        let set = line.set
        return [
            day.string(from: line.session.date),
            line.session.notes,
            line.exercise?.name ?? "",
            line.entry.notes,
            String(set.order + 1),
            decimal(set.weight.converted(to: unit), places: 3),
            String(set.reps),
            set.rpe.map { decimal($0, places: 2) } ?? "",
            set.rir.map(String.init) ?? "",
            set.isWarmup ? "warmup" : "working",
            set.isCompleted ? "completed" : "failed",
            set.modifiers.map(\.rawValue).joined(separator: ";"),
            set.notes,
        ]
    }

    /// Sessions in the order the rest of the app reads them: by day, then by identifier.
    ///
    /// The identifier is the tiebreak because a day can hold two workouts and a file whose row order
    /// depended on how the store happened to answer is a file two exports of one log disagree about.
    private static func chronological(_ lhs: WorkoutSession, _ rhs: WorkoutSession) -> Bool {
        lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date < rhs.date
    }

    /// Joins one row's fields, escaping each, and terminates it.
    private static func row(_ fields: [String]) -> String {
        fields.map(escaped).joined(separator: ",") + "\r\n"
    }

    /// RFC 4180 escaping: a field is quoted when it holds a separator, a quote, a line break or an
    /// edge space, and a quote inside a quoted field is doubled.
    ///
    /// The edge space is not RFC 4180's rule and is deliberate: a note the lifter typed with a
    /// trailing space is a note some readers trim, and a quoted field is the only way to say the
    /// space was theirs.
    private static func escaped(_ field: String) -> String {
        let needsQuoting =
            field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            || field.hasPrefix(" ") || field.hasSuffix(" ")
        guard needsQuoting else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// A number with at most `places` decimals, trailing zeros trimmed, always a full stop.
    ///
    /// `String(format:)` takes no locale and so writes the C one — which is the point rather than an
    /// accident. `100` reads as `100` rather than `100.000`, because the column is read by a person
    /// as often as by a parser.
    private static func decimal(_ value: Double, places: Int) -> String {
        var text = String(format: "%.\(places)f", value)
        guard text.contains(".") else { return text }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The heading's unit suffix. Not `SettingsStrings`' abbreviation: that one is copy and moves
    /// with the language, and a column name must not.
    private static func symbol(for unit: MassUnit) -> String {
        switch unit {
        case .kilograms: "kg"
        case .pounds: "lb"
        }
    }

    /// One date as `yyyy-MM-dd`, for a caller that formats one rather than a column of them.
    ///
    /// - Parameters:
    ///   - date: The day to write.
    ///   - timeZone: The zone to read it in.
    /// - Returns: The date, in the same spelling the `date` column uses.
    static func day(_ date: Date, in timeZone: TimeZone = .current) -> String {
        dayFormatter(timeZone).string(from: date)
    }

    /// `yyyy-MM-dd` in a fixed locale, so the date column sorts and parses everywhere.
    private static func dayFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        return formatter
    }
}
