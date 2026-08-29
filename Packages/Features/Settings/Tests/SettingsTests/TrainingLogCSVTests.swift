import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Settings

/// `FR-1.11.1`'s CSV half: one row per set, in a file a spreadsheet opens.
@Suite("Training log CSV")
struct TrainingLogCSVTests {
    /// GMT, so the `date` column is the same string wherever this runs. The zone is a parameter
    /// precisely because a real export uses the lifter's own.
    static let utc = TimeZone.gmt

    /// One instant, with a sub-second component, that reads as 2025-07-06 in GMT.
    static let stamp = Date(timeIntervalSinceReferenceDate: 773_452_800.123_456_7)

    /// An archive of exactly the rows a test names.
    ///
    /// - Parameters:
    ///   - exercises: The catalogue.
    ///   - sessions: The workouts.
    ///   - entries: The slots.
    ///   - sets: The sets.
    /// - Returns: The archive.
    static func archive(
        exercises: [Exercise] = [],
        sessions: [WorkoutSession] = [],
        entries: [ExerciseEntry] = [],
        sets: [SetEntry] = []
    ) -> TrainingLogArchive {
        TrainingLogArchive(
            exportedAt: stamp,
            exercises: exercises,
            sessions: sessions,
            entries: entries,
            sets: sets,
            bodyweight: [])
    }

    /// The rendered file, split into its rows with the terminator removed.
    ///
    /// - Parameters:
    ///   - archive: What to render.
    ///   - unit: The unit to write weights in.
    /// - Returns: The rows, heading first.
    static func rows(_ archive: TrainingLogArchive, unit: MassUnit = .kilograms) -> [String] {
        let lines = TrainingLogCSV.render(archive, unit: unit, timeZone: utc)
            .components(separatedBy: "\r\n")
        return Array(lines.dropLast())
    }

    /// A one-session, one-exercise archive whose sets a test then names.
    ///
    /// - Parameters:
    ///   - build: The sets, given the entry they hang off.
    ///   - notes: The session note.
    ///   - entryNotes: The slot's note.
    /// - Returns: The archive.
    static func oneEntry(
        sets build: (UUID) -> [SetEntry],
        notes: String = "",
        entryNotes: String = ""
    ) -> TrainingLogArchive {
        let exerciseID = ExportRecords.id(1)
        let sessionID = ExportRecords.id(2)
        let entryID = ExportRecords.id(3)
        return archive(
            exercises: [ExportRecords.exercise(id: exerciseID, name: "Back Squat", at: stamp)],
            sessions: [ExportRecords.session(id: sessionID, at: stamp, notes: notes)],
            entries: [
                ExportRecords.entry(
                    id: entryID,
                    sessionID: sessionID,
                    exerciseID: exerciseID,
                    at: stamp,
                    notes: entryNotes)
            ],
            sets: build(entryID))
    }

    @Test("The heading row names every column, and names the unit the weight is in")
    func headingsNameTheUnit() {
        #expect(
            TrainingLogCSV.headings(for: .kilograms) == [
                "date", "session_notes", "exercise", "exercise_notes", "set_number", "weight_kg",
                "reps", "rpe", "rir", "set_type", "outcome", "modifiers", "set_notes",
            ])
        #expect(TrainingLogCSV.headings(for: .pounds).contains("weight_lb"))
    }

    @Test("One row per set, with the values the lifter logged")
    func writesOneRowPerSet() {
        let log = Self.oneEntry(
            sets: { entryID in
                [
                    ExportRecords.set(
                        entryID: entryID,
                        at: Self.stamp,
                        order: 0,
                        grams: 60_000,
                        reps: 5,
                        isWarmup: true),
                    ExportRecords.set(
                        entryID: entryID,
                        at: Self.stamp,
                        order: 1,
                        grams: 102_500,
                        reps: 5,
                        rpe: 8.5,
                        rir: 1,
                        modifiers: [SetModifier(.belt), SetModifier(.sleeves)],
                        notes: "solid"),
                    ExportRecords.set(
                        entryID: entryID,
                        at: Self.stamp,
                        order: 2,
                        grams: 102_500,
                        reps: 0,
                        isCompleted: false),
                ]
            },
            notes: "felt good",
            entryNotes: "paused")
        let rows = Self.rows(log)
        let lead = "2025-07-06,felt good,Back Squat,paused"
        #expect(rows.count == 4)
        #expect(rows[1] == "\(lead),1,60,5,,,warmup,completed,,")
        #expect(rows[2] == "\(lead),2,102.5,5,8.5,1,working,completed,belt;sleeves,solid")
        #expect(rows[3] == "\(lead),3,102.5,0,,,working,failed,,")
    }

    @Test("An empty log is a heading row and nothing else")
    func writesTheHeadingsAlone() {
        let rows = Self.rows(Self.archive())
        #expect(rows.count == 1)
        #expect(rows[0].hasPrefix("date,"))
    }

    @Test("Rows are terminated CRLF, per RFC 4180")
    func terminatesRowsForEveryReader() {
        let text = TrainingLogCSV.render(Self.archive(), unit: .kilograms, timeZone: Self.utc)
        let headings = TrainingLogCSV.headings(for: .kilograms).joined(separator: ",")
        #expect(text == headings + "\r\n")
    }

    @Test("A note carrying a separator, a quote, a line break or an edge space is quoted")
    func escapesTheLiftersOwnWords() {
        let log = Self.oneEntry(sets: { entryID in
            ["hips, then knees", "coach said \"stop\"", "first\nsecond", " trailing ", "bare\rreturn"]
                .enumerated()
                .map { order, note in
                    ExportRecords.set(
                        entryID: entryID,
                        at: Self.stamp,
                        order: order,
                        notes: note)
                }
        })
        let rows = Self.rows(log)
        #expect(rows[1].hasSuffix("\"hips, then knees\""))
        #expect(rows[2].hasSuffix("\"coach said \"\"stop\"\"\""))
        // The embedded newline is inside a quoted field, so the row is split across two lines of
        // the file and RFC 4180 says a reader rejoins them. Splitting on CRLF cannot see that, so
        // the whole text is what this asserts on.
        let text = TrainingLogCSV.render(log, unit: .kilograms, timeZone: Self.utc)
        #expect(text.contains("\"first\nsecond\""))
        #expect(text.contains("\" trailing \""))
        // A lone carriage return is the same problem as a line feed and a separate clause in the
        // rule, so it is asserted separately: a reader that met an unquoted one would end the row
        // there and read the rest of the note as the next row's first field.
        #expect(text.contains("\"bare\rreturn\""))
    }

    @Test("The weight is written in the unit the heading names")
    func convertsToTheDisplayUnit() {
        let log = Self.oneEntry(sets: {
            [ExportRecords.set(entryID: $0, at: Self.stamp, grams: 102_500)]
        })
        #expect(Self.rows(log, unit: .kilograms)[1].contains(",102.5,"))
        // 102.5 kg is 225.9739… lb, written to three decimals. That is where the CSV stops being
        // the lossless half — a rounding of under half a gram, and the exact grams are the JSON's.
        #expect(Self.rows(log, unit: .pounds)[1].contains(",225.974,"))
    }

    @Test("A whole number carries no decimal point at all")
    func trimsTrailingZeros() {
        let log = Self.oneEntry(sets: {
            [ExportRecords.set(entryID: $0, at: Self.stamp, grams: 100_000)]
        })
        #expect(Self.rows(log)[1].contains(",100,5,"))
    }

    @Test("An assisted set keeps its sign")
    func keepsANegativeLoad() {
        let log = Self.oneEntry(sets: {
            [ExportRecords.set(entryID: $0, at: Self.stamp, grams: -22_500)]
        })
        #expect(Self.rows(log)[1].contains(",-22.5,"))
    }

    @Test("Rows are ordered by day, then by session, then by entry, then by set")
    func ordersChronologically() {
        let log = Self.twoSessions()
        // Three rows from the older session, in entry-then-set order, and none from the newer one:
        // it has no entries, so it contributes no rows at all.
        let rows = Self.rows(log)
        #expect(rows.count == 4)
        #expect(rows[1].contains("2025-07-03,,Bench,,1,100,1,"))
        #expect(rows[2].contains("2025-07-03,,Bench,,2,100,2,"))
        #expect(rows[3].contains("2025-07-03,,Bench,,1,100,3,"))
    }

    /// Two sessions handed over newest-first, with the older one's entries and sets shuffled.
    ///
    /// The order in is the order the history screens read in, so a renderer that trusted its input
    /// would write the file upside down.
    ///
    /// - Returns: The archive.
    static func twoSessions() -> TrainingLogArchive {
        let exerciseID = ExportRecords.id(4)
        let older = ExportRecords.id(0x11)
        let newer = ExportRecords.id(0x22)
        let firstEntry = ExportRecords.id(5)
        let secondEntry = ExportRecords.id(6)
        let threeDaysBack = stamp.addingTimeInterval(-3 * 86_400)
        return archive(
            exercises: [ExportRecords.exercise(id: exerciseID, name: "Bench", at: stamp)],
            sessions: [
                ExportRecords.session(id: newer, at: stamp),
                ExportRecords.session(id: older, at: threeDaysBack),
            ],
            entries: [
                ExportRecords.entry(
                    id: secondEntry,
                    sessionID: older,
                    exerciseID: exerciseID,
                    at: threeDaysBack,
                    order: 1),
                ExportRecords.entry(
                    id: firstEntry,
                    sessionID: older,
                    exerciseID: exerciseID,
                    at: threeDaysBack,
                    order: 0),
            ],
            sets: [
                ExportRecords.set(entryID: secondEntry, at: stamp, order: 0, reps: 3),
                ExportRecords.set(entryID: firstEntry, at: stamp, order: 1, reps: 2),
                ExportRecords.set(entryID: firstEntry, at: stamp, order: 0, reps: 1),
            ])
    }

    @Test("Two workouts on one day are ordered by identifier, so two exports agree")
    func breaksATieOnTheIdentifier() {
        // The clause `ordersChronologically` never reaches: its sessions are three days apart, so
        // the date alone decides them and the tiebreak could be reversed without any test noticing.
        // A day holding two workouts is what the tiebreak exists for — without it the row order is
        // whatever order the store happened to answer in, and two exports of one log disagree.
        let rows = Self.rows(Self.sameDaySessions())
        #expect(rows.count == 3)
        #expect(rows[1].hasPrefix("2025-07-06,morning,"))
        #expect(rows[2].hasPrefix("2025-07-06,evening,"))
    }

    /// Two workouts on one day, handed over with the later identifier first.
    ///
    /// `ExportRecords.id(_:)` orders by its byte under the string comparison the tiebreak uses, so
    /// `0x11` precedes `0x22` — and the array is built the other way round, so a renderer that
    /// trusted its input rather than sorting would write these two rows the wrong way about.
    ///
    /// - Returns: The archive.
    static func sameDaySessions() -> TrainingLogArchive {
        let exerciseID = ExportRecords.id(4)
        let morning = ExportRecords.id(0x11)
        let evening = ExportRecords.id(0x22)
        let morningEntry = ExportRecords.id(7)
        let eveningEntry = ExportRecords.id(8)
        return archive(
            exercises: [ExportRecords.exercise(id: exerciseID, name: "Bench", at: stamp)],
            sessions: [
                ExportRecords.session(id: evening, at: stamp, notes: "evening"),
                ExportRecords.session(id: morning, at: stamp, notes: "morning"),
            ],
            entries: [
                ExportRecords.entry(
                    id: eveningEntry, sessionID: evening, exerciseID: exerciseID, at: stamp),
                ExportRecords.entry(
                    id: morningEntry, sessionID: morning, exerciseID: exerciseID, at: stamp),
            ],
            sets: [
                ExportRecords.set(entryID: eveningEntry, at: stamp),
                ExportRecords.set(entryID: morningEntry, at: stamp),
            ])
    }

    @Test("A day is read in the zone it is asked for")
    func readsTheDayInTheGivenZone() throws {
        let log = Self.oneEntry(sets: { [ExportRecords.set(entryID: $0, at: Self.stamp)] })
        let behind = try #require(TimeZone(identifier: "America/Los_Angeles"))
        // The stamp is midnight GMT, so a zone behind it lands on the previous date. The zone is a
        // parameter because a session's date is the day it was logged on, in the calendar it was
        // logged in — a fixed zone here moves a real workout onto a day it did not happen.
        #expect(TrainingLogCSV.day(Self.stamp, in: Self.utc) == "2025-07-06")
        #expect(TrainingLogCSV.day(Self.stamp, in: behind) == "2025-07-05")
        let text = TrainingLogCSV.render(log, unit: .kilograms, timeZone: behind)
        #expect(text.contains("2025-07-05,"))
    }
}
