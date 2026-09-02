import Foundation

/// Which of an exercise's two names a screen shows (`FR-1.14.2`).
///
/// **Two cases rather than a language code, because two is what the schema holds.**
/// ``Exercise/ukrainianName`` is one column, so "which name" has exactly two answers and a code
/// carried around as a `String` would invite a third that resolves to nothing. A later language is
/// a column and a case, together.
///
/// **A state that bakes a name into a value its rows draw takes this as a settable property, which
/// its view sets from `@Environment(\.locale)` before the read.** A state that resolved the locale
/// itself would answer differently from the rows above it in a snapshot or a preview, where the
/// environment is the only locale there is, and a test could reach it only by changing the process.
/// Every such property defaults to ``english``, so a view that forgets the line shows English rather
/// than nothing — a row that can reach the environment itself should read it there and need no
/// property at all.
public enum ExerciseNameLanguage: CaseIterable, Sendable {
    /// ``Exercise/name`` — the name every exercise has.
    case english

    /// ``Exercise/ukrainianName`` where one is set, and ``english`` where none is.
    case ukrainian

    /// The language `locale` asks an exercise name to be shown in.
    ///
    /// Ukrainian for Ukrainian and English for everything else — including the languages nothing
    /// here translates into, whose speakers get the name the catalogue was authored in rather than
    /// a blank.
    ///
    /// **Matched on the language, never on the region.** `uk_UA` and a bare `uk` are the same
    /// answer, and `en_GB` — whose region is the United Kingdom — is not Ukrainian.
    ///
    /// - Parameter locale: The locale a screen is rendering in.
    public init(_ locale: Locale) {
        self = locale.language.languageCode?.identifier == "uk" ? .ukrainian : .english
    }
}

extension Exercise {
    /// The name to show in `language`, which is never blank (`FR-1.14.2`).
    ///
    /// **English is the fallback in both directions of missing.** A Ukrainian name that was never
    /// set and one that was set to whitespace resolve identically, so clearing the form's second
    /// field returns the exercise to its English name rather than leaving a row with no readable
    /// name at all.
    ///
    /// ``name`` itself is returned as stored, blank included: a blank there is a defect the create
    /// form refuses and this accessor cannot repair, and substituting anything would hide it.
    ///
    /// - Parameter language: Which name the screen wants.
    /// - Returns: The name in `language`, or the English one where there is nothing to show.
    public func displayName(in language: ExerciseNameLanguage) -> String {
        guard language == .ukrainian, let ukrainianName else { return name }
        let trimmed = ukrainianName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    /// The name to show in `locale`.
    ///
    /// The accessor a screen calls, `locale` being what SwiftUI's environment already carries.
    ///
    /// - Parameter locale: The locale the screen is rendering in.
    /// - Returns: The name in that locale's language, or the English one.
    public func displayName(for locale: Locale) -> String {
        displayName(in: ExerciseNameLanguage(locale))
    }
}
