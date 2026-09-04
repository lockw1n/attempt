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
    /// - Parameter sets: How many consecutive sets the schemes in this column ask for.
    /// - Returns: The heading.
    static func recordsSetColumn(_ sets: Int) -> LocalizedStringResource {
        resource("exerciselibrary.records.column \(sets)")
    }

    /// The corner cell, which heads the column of row headings.
    ///
    /// **A noun with no numeral in it, so it needs no plural rule** — the rows themselves are bare
    /// numerals, formatted for the locale like every other number in this app (`G-3.4`). Writing
    /// each row as "1 rep" / "3 reps" would be the one place in the module that wanted a
    /// `.stringsdict`, for a heading a reader takes in once.
    static let recordsRepsHeader = resource("exerciselibrary.records.reps-header")

    /// One scheme named the way a lifter writes it — `5 × 5`.
    ///
    /// **Their own notation rather than a sentence**, which is what the detail section's diagonal
    /// rows are headed with: `FR-1.6.1`'s "5-rep max" is the one-set column's spelling and says
    /// nothing about how many sets, so a two-dimensional record needs the two-dimensional name.
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

    /// This file's strings, for ``ExerciseLibraryStrings/all``.
    static var allSchemeRecordStrings: [LocalizedStringResource] {
        [
            recordsTableTitle, recordsAllSchemes, recordsAllSchemesHint,
            recordsSetColumn(5), recordsRepsHeader, recordsScheme(5, 5),
            recordsCellLabel(reps: 5, sets: 5, load: "100 kg", date: "1 May"),
        ]
    }
}
