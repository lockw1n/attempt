import Foundation

/// Whether an exercise's name matches what a user typed into a search field (`FR-1.14.3`,
/// `FR-18.1.1`).
///
/// **One home for the rule, beside ``ExerciseDisplayOrder``.** Every surface that searches exercise
/// names calls this, so no two of them can disagree about what a query finds.
///
/// **Every word, in any order.** The query splits on whitespace and a name matches when it contains
/// each word, so "row cable" finds "Cable row" and "row barbell" does not. A run of spaces, or a
/// trailing one, is no word at all: it neither matches everything nor excludes anything. One word
/// behaves as a plain substring search, and whitespace-only input is no search — otherwise the
/// first space typed empties the screen. A word must appear as typed; an inflected form of it is
/// not found.
///
/// **`localizedStandardContains`, never a hand-rolled `lowercased().contains`**: it ignores case
/// *and* diacritics, so "sumo" finds "Sumó" and a Turkish locale does not lose the dotted I.
///
/// **The caller passes the name the row is showing, never the record's two fields in turn.**
/// `FR-1.14.3` says the name shown, and the two readings disagree exactly where it matters: an
/// English query would otherwise find a row whose visible name is Cyrillic and holds none of what
/// was typed, and a Ukrainian name left as whitespace — which ``Exercise/displayName(in:)``
/// deliberately renders as the English one — would be searchable under a name nothing on screen
/// says.
public enum ExerciseNameSearch {
    /// Whether `name` contains every word of `query`.
    ///
    /// - Parameters:
    ///   - name: The name the row is showing.
    ///   - query: What the user typed, untrimmed.
    /// - Returns: Whether to show the row.
    public static func matches(_ name: String, query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy { word in
            name.localizedStandardContains(word)
        }
    }
}
