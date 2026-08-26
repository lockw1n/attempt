import Foundation

/// One session reduced to everything `FR-1.5.4` can look for in it.
///
/// **The summary is the index.** Two of the three searchable fields — the exercise names and the
/// session's own note — are already on ``SessionSummary`` because the row draws them, so the only
/// thing this adds is the per-set notes, which nothing on screen shows. Building a second, parallel
/// index of names and dates would be a second answer to what a session is.
///
/// **`ExerciseEntry.notes` is deliberately absent.** Every writer in this app stores it as the empty
/// string and no screen offers a field for it, so a search over it would match nothing and a fourth
/// "matched in" label would be copy for a state that cannot arise. If a surface ever writes one,
/// this type and ``MatchedFields`` are where it joins.
struct IndexedSession: Identifiable, Equatable, Sendable {
    /// The row this session would draw as, already summarised.
    let summary: SessionSummary

    /// The per-set notes logged under it (`FR-1.2.3`), in the order the sets were performed.
    ///
    /// **Empty notes are dropped on the way in**, which is nearly all of them: a note is the
    /// exception rather than the column's normal value, and an index carrying one empty string per
    /// set would be the memory `NFR-1.5` is about.
    let setNotes: [String]

    /// The session's identifier, which is also its row's.
    var id: UUID { summary.id }
}

/// Where in a session a query was found (`FR-1.5.4`).
///
/// An option set rather than one case, because a query can match in more than one place at once —
/// "squat" typed against a squat day whose note also says *squat* matched twice, and a result row
/// that named only the first would be telling the user something narrower than the truth.
struct MatchedFields: OptionSet, Hashable, Sendable {
    /// The bits set. `OptionSet`'s `init(rawValue:)` is the synthesized memberwise one.
    let rawValue: Int

    /// An exercise performed in the session is named by the query.
    static let exerciseName = MatchedFields(rawValue: 1 << 0)

    /// The session's own note contains it (`FR-1.2.9`).
    static let sessionNote = MatchedFields(rawValue: 1 << 1)

    /// A note on one of its sets contains it (`FR-1.2.3`).
    static let setNote = MatchedFields(rawValue: 1 << 2)
}

/// Why one session is in the results.
///
/// **`FR-1.5.4` does not ask for this and the row is misleading without it.** A session that matched
/// on a *set* note draws nothing the query appears in — the card shows the day, the exercises, the
/// session note and two numbers — so a result list without it is a set of rows the user cannot
/// account for. The other two fields are visible on the card already; they are named anyway, because
/// a row that explains itself only sometimes is worse than one that always does.
struct SearchMatch: Equatable, Sendable {
    /// Which fields the query was found in. Never empty — a match with nothing set is not a match.
    let fields: MatchedFields

    /// The first per-set note the query was found in, or `nil` where none was.
    ///
    /// Carried rather than derived on screen because the card holds no sets: this string is the only
    /// evidence of a set-note match that ever reaches the row.
    let setNote: String?
}

/// One row of the results: the session, and why it is here.
struct SessionMatch: Identifiable, Equatable, Sendable {
    /// The row to draw.
    let summary: SessionSummary

    /// Where the query was found in it.
    let match: SearchMatch

    /// The session's identifier, which is also the identifier its route carries.
    var id: UUID { summary.id }
}

/// History search (`FR-1.5.4`) as free functions over values, so every claim about *which sessions
/// come back* is testable without a repository or a screen.
enum SessionSearch {
    /// `text` with its surrounding whitespace removed — what the rest of this type takes.
    ///
    /// Whitespace-only input is no search at all, for `ExerciseListState`'s reason: otherwise the
    /// first space typed empties the screen.
    ///
    /// - Parameter text: What the user typed.
    /// - Returns: The query, empty where there is none.
    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The sessions `query` was found in, in the order they were given.
    ///
    /// The order is the caller's and is not touched, which is how the results stay
    /// reverse-chronological: they are a filter of a list the repository already ordered.
    ///
    /// - Parameters:
    ///   - sessions: Every indexed session, newest first.
    ///   - query: The trimmed query. An empty one matches nothing here — *every* session is the
    ///     unsearched list's answer, and this function is only ever asked the searched one.
    /// - Returns: The matching rows.
    static func results(in sessions: [IndexedSession], matching query: String) -> [SessionMatch] {
        guard !query.isEmpty else { return [] }
        return sessions.compactMap { session in
            match(session, query: query).map { SessionMatch(summary: session.summary, match: $0) }
        }
    }

    /// Where `query` appears in one session, or `nil` if it does not appear at all.
    ///
    /// **`localizedStandardContains` throughout**, for `ExerciseListState`'s reason: it ignores case
    /// *and* diacritics, so "sumo" finds "Sumó" and a Turkish locale does not lose the dotted I. A
    /// hand-rolled `lowercased().contains` is a different search and a worse one.
    ///
    /// - Parameters:
    ///   - session: The session to test.
    ///   - query: The trimmed, non-empty query.
    /// - Returns: The match, or `nil`.
    static func match(_ session: IndexedSession, query: String) -> SearchMatch? {
        guard !query.isEmpty else { return nil }
        var fields: MatchedFields = []

        if session.summary.exerciseNames.contains(where: { $0.localizedStandardContains(query) }) {
            fields.insert(.exerciseName)
        }
        if session.summary.notes.localizedStandardContains(query) {
            fields.insert(.sessionNote)
        }
        let setNote = session.setNotes.first { $0.localizedStandardContains(query) }
        if setNote != nil {
            fields.insert(.setNote)
        }

        guard !fields.isEmpty else { return nil }
        return SearchMatch(fields: fields, setNote: setNote)
    }
}
