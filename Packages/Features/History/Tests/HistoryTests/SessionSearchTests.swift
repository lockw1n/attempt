import Foundation
import PowerliftingCore
import Testing

@testable import History

/// The matcher behind `FR-1.5.4`, as values: which sessions come back, and what a row is told about
/// why it is here.
///
/// Separate from the state's own suite because these are claims about *matching* rather than about
/// reading — a store is not needed to decide whether "sumo" finds "Sumó", and a test that built one
/// would be asserting the repository's behaviour alongside the matcher's.
@Suite("History search matching")
struct SessionSearchTests {
    @Test("An exercise name matches on a substring, ignoring case and diacritics")
    func exerciseNameMatches() {
        let session = Fixture.session(exercises: ["Sumó Deadlift", "Bench Press"])

        for query in ["sumo", "SUMO", "Sumó", "deadlift", "ench"] {
            #expect(
                SessionSearch.match(session, query: query)?.fields == .exerciseName,
                "\(query) should have matched an exercise name"
            )
        }
    }

    @Test("A query in none of the three fields is not a match")
    func nothingMatches() {
        let session = Fixture.session(
            exercises: ["Back Squat"], notes: "Felt heavy.", setNotes: ["Belt on."])

        #expect(SessionSearch.match(session, query: "deadlift") == nil)
        #expect(SessionSearch.match(session, query: "light") == nil)
    }

    @Test("The session's own note matches, and the row is told it was the note")
    func sessionNoteMatches() throws {
        let session = Fixture.session(exercises: ["Back Squat"], notes: "Knee felt off today.")

        let match = try #require(SessionSearch.match(session, query: "knee"))
        #expect(match.fields == .sessionNote)
        // Nothing here came from a set, so the row has no set note to draw.
        #expect(match.setNote == nil)
    }

    @Test("A per-set note matches, and the note itself travels to the row")
    func setNoteMatches() throws {
        let session = Fixture.session(
            exercises: ["Back Squat"], setNotes: ["Grip slipped", "Belt on, felt fast"])

        let match = try #require(SessionSearch.match(session, query: "belt"))
        #expect(match.fields == .setNote)
        // The *matching* note, not the first one: a row showing "Grip slipped" for a query of
        // "belt" would be evidence of nothing.
        #expect(match.setNote == "Belt on, felt fast")
    }

    @Test("One query can match all three fields at once, and all three are reported")
    func everyFieldMatches() throws {
        let session = Fixture.session(
            exercises: ["Back Squat"],
            notes: "Squat day.",
            setNotes: ["Squat felt fast"]
        )

        let match = try #require(SessionSearch.match(session, query: "squat"))
        #expect(match.fields == [.exerciseName, .sessionNote, .setNote])
        #expect(match.setNote == "Squat felt fast")
    }

    @Test("An empty query matches nothing here — every session is the unsearched list's answer")
    func emptyQueryMatchesNothing() {
        let session = Fixture.session(exercises: ["Back Squat"], notes: "Felt heavy.")

        #expect(SessionSearch.match(session, query: "") == nil)
        #expect(SessionSearch.results(in: [session], matching: "").isEmpty)
    }

    @Test("Results keep the order they were given, which is what keeps them reverse-chronological")
    func resultsKeepOrder() {
        let sessions = (0..<4).map { index in
            Fixture.session(index: index, exercises: ["Back Squat"], notes: "Squat")
        }

        let results = SessionSearch.results(in: sessions, matching: "squat")
        #expect(results.count == 4)
        #expect(results.map(\.id) == sessions.map(\.id))
    }

    @Test("Results carry the summary of the session that matched, not a rebuilt one")
    func resultsCarryTheirSummary() {
        let matching = Fixture.session(index: 0, exercises: ["Back Squat"])
        let other = Fixture.session(index: 1, exercises: ["Bench Press"])

        let results = SessionSearch.results(in: [matching, other], matching: "squat")
        #expect(results.count == 1)
        #expect(results.first?.summary == matching.summary)
    }

    @Test("Surrounding whitespace is not part of the query, and whitespace alone is no query")
    func trimming() {
        #expect(SessionSearch.trimmed("  squat \n") == "squat")
        #expect(SessionSearch.trimmed("   ").isEmpty)
        #expect(SessionSearch.trimmed("").isEmpty)
    }

    /// Indexed sessions built as values — the matcher never reads a store.
    private enum Fixture {
        /// One indexed session.
        ///
        /// - Parameters:
        ///   - index: Which session, so two fixtures in one test have different identifiers.
        ///   - exercises: What was trained.
        ///   - notes: The session's own note (`FR-1.2.9`).
        ///   - setNotes: The per-set notes under it (`FR-1.2.3`).
        /// - Returns: The value.
        static func session(
            index: Int = 0,
            exercises: [String],
            notes: String = "",
            setNotes: [String] = []
        ) -> IndexedSession {
            IndexedSession(
                summary: SessionSummary(
                    id: identifier(index),
                    date: Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 86_400),
                    exerciseNames: exercises,
                    setCount: 3,
                    tonnage: Weight(grams: 1_000_000),
                    notes: notes
                ),
                setNotes: setNotes
            )
        }

        /// A stable identifier, so an order assertion is about order rather than about `UUID()`.
        ///
        /// - Parameter index: Which session.
        /// - Returns: The identifier.
        static func identifier(_ index: Int) -> UUID {
            UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index))") ?? UUID()
        }
    }
}
