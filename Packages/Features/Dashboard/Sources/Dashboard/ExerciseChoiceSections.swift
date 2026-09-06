import Foundation

/// One of the picker's two sections (`FR-16.5.3`).
struct ExerciseChoiceSection: Identifiable, Sendable, Equatable {
    /// Which section this is — the two are headed differently and ordered differently.
    enum Kind: Sendable, Hashable {
        /// Exercises with a completed working set in the lookback window, most recent first.
        case trained

        /// Everything else in the catalogue, by name.
        case everythingElse
    }

    /// Which section.
    let kind: Kind

    /// Its rows, in the order they are drawn.
    let choices: [TiledExerciseChoice]

    /// See `Identifiable`. A section appears once.
    var id: Kind { kind }
}

/// How a picker splits and orders its rows (`FR-16.5.3`).
///
/// **A type of its own, and pure**, because every claim in `FR-16.5.3` is a claim about which rows
/// come back and in what order — testable only where the answer is computed, and shared by the two
/// screens that draw this list rather than restated on each.
///
/// **Two orderings, coexisting rather than one replacing the other.** `FR-1.14.2`'s alphabetical
/// order in the screen's own locale is what the caller hands in and what **Everything else** keeps;
/// recency is a second ordering, and it applies inside **Trained** only. The alternative — ranking
/// the whole list by recency — would leave the catalogue's 130-odd untrained rows in whatever order
/// the tie-break happened to give them, which is no order a reader can scan.
///
/// **Ties inside Trained break on the name, not on the identifier.** Two exercises trained on the
/// same day are equally recent, and a day is the finest grain a session date has (`FR-1.2.1` dates a
/// workout, not an instant) — so same-day ties are the common case here rather than the freak one
/// ``RepositoryInterface/ExerciseDisplayOrder`` guards against, and a reader scanning a day's worth
/// of rows wants them alphabetical.
enum ExerciseChoiceSections {
    /// The rows matching `query`, split into the two sections and ordered.
    ///
    /// **A section with nothing in it is dropped**, so a lifter who has never trained sees one
    /// unheaded-looking list rather than an empty **Trained** heading claiming a section exists.
    ///
    /// **Both sections are searched, not just one.** The query narrows the population first and the
    /// split happens after, which is what makes a search over an exercise trained last week find it
    /// where it actually is.
    ///
    /// - Parameters:
    ///   - choices: Every row the screen may show, already in `FR-1.14.2`'s order.
    ///   - query: What the user typed. Whitespace-only is no search at all — otherwise the first
    ///     space typed empties the screen.
    /// - Returns: The sections with rows in them, **Trained** first.
    static func sections(
        _ choices: [TiledExerciseChoice], matching query: String
    ) -> [ExerciseChoiceSection] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = choices.filter { matches($0, query: query) }
        // Paired with its date rather than sorted on an optional, so the comparator has no branch
        // for a value the split has already excluded — the section is defined by the date being
        // there, and a `?? .distantPast` would be an unreachable answer to that question.
        let trained =
            found
            .compactMap { choice in choice.lastTrained.map { DatedChoice(date: $0, choice: choice) } }
            .sorted { left, right in
                if left.date != right.date { return left.date > right.date }
                return left.choice.name.localizedStandardCompare(right.choice.name)
                    == .orderedAscending
            }
            .map(\.choice)
        let rest = found.filter { $0.lastTrained == nil }
        return [
            ExerciseChoiceSection(kind: .trained, choices: trained),
            ExerciseChoiceSection(kind: .everythingElse, choices: rest),
        ]
        .filter { !$0.choices.isEmpty }
    }

    /// A row and the date that puts it in the **Trained** section, so the sort reads no optional.
    private struct DatedChoice {
        /// When it was last trained.
        let date: Date

        /// The row.
        let choice: TiledExerciseChoice
    }

    /// Whether one row's name matches what the user typed.
    ///
    /// `localizedStandardContains`, `ExerciseListState.matchesSearch(_:)`'s rule and for its
    /// reasons: it ignores case *and* diacritics, and it is matched against the name the row is
    /// actually showing (`FR-1.14.3`) rather than against either of the record's two fields.
    ///
    /// - Parameters:
    ///   - choice: The row.
    ///   - query: The search text, already trimmed.
    /// - Returns: Whether to show it.
    private static func matches(_ choice: TiledExerciseChoice, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return choice.name.localizedStandardContains(query)
    }
}
