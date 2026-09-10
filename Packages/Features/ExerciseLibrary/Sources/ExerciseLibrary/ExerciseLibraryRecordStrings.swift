import Foundation

/// ``ExerciseLibraryStrings``' second file — `FR-16.2.4`'s record table.
///
/// **The same type in a second file, on ``Logging/LoggingStrings``' argument**: one enum is what
/// keeps a module's copy in one place, and `file_length` is what keeps that one place readable.
///
/// The seam is the requirement rather than the size: a scheme record is `FR-16.2`'s, and the strings
/// below belong to a screen of its own rather than to `FR-1.1.6`'s detail.
extension ExerciseLibraryStrings {
    // MARK: - The scheme table (FR-16.2.4)

    /// The table screen's own title.
    static let recordsTableTitle = resource("exerciselibrary.records.title")

    /// The control on the detail section that opens it.
    ///
    /// **What is behind it rather than a verb**, on ``recordsMore``'s rule.
    static let recordsAllSchemes = resource("exerciselibrary.detail.records.all")

    /// What that control opens, as VoiceOver reads it (`G-4.2`).
    static let recordsAllSchemesHint = resource("exerciselibrary.detail.records.all.hint")

    /// One column's heading — the set count the column stands at.
    ///
    /// **The one-set column is headed by a word, never `× 1`** (`FR-17.2.3`). Nobody writes their
    /// heaviest single a "× 1"; the column is the single sets, and saying so is what stops the
    /// heading reading as a notation the app invented.
    ///
    /// - Parameter sets: How many consecutive sets the schemes in this column were performed at.
    /// - Returns: The heading.
    static func recordsSetColumn(_ sets: Int) -> LocalizedStringResource {
        sets == 1
            ? resource("exerciselibrary.records.column.single")
            : resource("exerciselibrary.records.column \(sets)")
    }

    /// The corner cell, which heads the column of row headings.
    ///
    /// **A noun with no numeral in it, so it needs no plural rule** — the rows themselves are bare
    /// numerals, formatted for the locale like every other number in this app (`G-3.4`). Writing
    /// each row as "1 rep" / "3 reps" would be the one place in the module that wanted a
    /// `.stringsdict`, for a heading a reader takes in once.
    static let recordsRepsHeader = resource("exerciselibrary.records.reps-header")

    /// One scheme named the way a lifter writes it — `5×5` (`FR-17.2.3`).
    ///
    /// **Their own notation rather than a sentence**, which is what the detail section's diagonal
    /// rows are headed with. Tight rather than spaced, so the badge, the feed and this table all
    /// write a scheme the same way.
    ///
    /// - Parameters:
    ///   - reps: The N.
    ///   - sets: How many consecutive sets at it.
    /// - Returns: The name.
    static func recordsScheme(_ reps: Int, _ sets: Int) -> LocalizedStringResource {
        resource("exerciselibrary.records.scheme \(reps) \(sets)")
    }

    /// One cell as VoiceOver reads it — "5 by 5, 100 kilograms, 1 May" (`G-4.2`).
    ///
    /// **The whole cell in one string, because the cell draws neither heading.** A cell's scheme is
    /// its row's and its column's, which a reader moving through a grid does not carry with them;
    /// combining the children would announce a load and a date belonging to nothing.
    ///
    /// **The load and the date arrive already rendered**, on ``Logging/LoggingStrings/setRPE(_:)``'s
    /// rule: both are formatted for the locale by the caller's own formatter (`G-3.4`), and the word
    /// between the numerals is this string's.
    ///
    /// - Parameters:
    ///   - reps: The N.
    ///   - sets: How many consecutive sets at it.
    ///   - load: The record load, formatted.
    ///   - date: The day it was set, formatted.
    /// - Returns: The label.
    static func recordsCellLabel(
        reps: Int, sets: Int, load: String, date: String
    ) -> LocalizedStringResource {
        resource("exerciselibrary.records.cell \(reps) \(sets) \(load) \(date)")
    }

    /// The caption under a first performance's load — `First · 1 May` (`FR-17.2.2`, `Q-17.1`).
    ///
    /// **The word the badge and the feed use**, so all three surfaces agree by sharing it. The cell
    /// still shows its day: a baseline is a real performance and the date is what makes it one.
    ///
    /// - Parameter date: The day it was performed, formatted.
    /// - Returns: The caption.
    static func recordsCellFirst(date: String) -> LocalizedStringResource {
        resource("exerciselibrary.records.cell.first \(date)")
    }

    /// What a never-performed cell says (`FR-17.2.2`, `Q-17.1`).
    ///
    /// **A word rather than a blank or a dash.** `G-4.5` forbids the state being carried by tint,
    /// and a dash reads as "no data" where this means "not done" — the shortest phrase that is a
    /// state and not a number.
    static let recordsCellNotYet = resource("exerciselibrary.records.cell.not-yet")

    /// A never-performed cell as VoiceOver reads it — "5 by 5, not yet" (`G-4.2`).
    ///
    /// **It names its scheme for ``recordsCellLabel(reps:sets:load:date:)``'s reason**: a reader
    /// moving across a grid does not carry the row and column headings with them, and "not yet"
    /// alone would be a state belonging to nothing.
    ///
    /// - Parameters:
    ///   - reps: The N.
    ///   - sets: How many consecutive sets at it.
    /// - Returns: The label.
    static func recordsCellNotYetLabel(reps: Int, sets: Int) -> LocalizedStringResource {
        resource("exerciselibrary.records.cell.not-yet.label \(reps) \(sets)")
    }

    /// A first performance's cell as VoiceOver reads it — "5 by 5, first time, 100 kilograms,
    /// 1 May" (`G-4.2`).
    ///
    /// - Parameters:
    ///   - reps: The N.
    ///   - sets: How many consecutive sets at it.
    ///   - load: The load, formatted.
    ///   - date: The day, formatted.
    /// - Returns: The label.
    static func recordsCellFirstLabel(
        reps: Int, sets: Int, load: String, date: String
    ) -> LocalizedStringResource {
        resource("exerciselibrary.records.cell.first.label \(reps) \(sets) \(load) \(date)")
    }

    /// This file's strings, for ``ExerciseLibraryStrings/all``.
    static var allSchemeRecordStrings: [LocalizedStringResource] {
        [
            recordsTableTitle, recordsAllSchemes, recordsAllSchemesHint,
            recordsSetColumn(5), recordsSetColumn(1), recordsRepsHeader, recordsScheme(5, 5),
            recordsCellLabel(reps: 5, sets: 5, load: "100 kg", date: "1 May"),
            recordsCellFirst(date: "1 May"), recordsCellNotYet,
            recordsCellNotYetLabel(reps: 5, sets: 5),
            recordsCellFirstLabel(reps: 5, sets: 5, load: "100 kg", date: "1 May"),
        ]
    }
}
