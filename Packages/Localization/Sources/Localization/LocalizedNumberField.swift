import Foundation
import PowerliftingCore

/// The crossing between a text field and a number, in the user's locale (`G-3.4`, `G-1.1`).
///
/// **Text, not numbers, and that is a failable initializer meeting a keyboard.** A `TextField` bound
/// to a `Double` reverts what the user is halfway through typing — "10" on the way to "102.5" is a
/// complete number, and a lone "." is not one at all — so every numeric field that takes one is a
/// `String` and the crossing happens once, on confirm. That crossing is the only place floating
/// point exists on the way in from a form: a parsed decimal becomes grams immediately and nothing
/// downstream sees the `Double`.
///
/// **One type rather than a copy per form**, because every form that reads a number — a set's
/// weight and RPE, a bar's mass, a manual e1RM (`FR-1.7.5`) — must read it the same way. A locale
/// that writes the decimal as a comma is not a property of what is being entered. It lives beside
/// ``AppFormat`` because it is that type's other direction: one writes a value out for the locale,
/// this reads one back in.
public enum LocalizedNumberField {
    /// Reads a decimal the user typed, in their locale.
    ///
    /// **The whole field has to be the number, and `lenient: false` does not say that.** Measured:
    /// `Double("2,5abc", format: .number.locale(de), lenient: false)` is **2.5**, and `"2 5"` is
    /// **2** — the strict flag narrows which *forms* parse, and still lets the strategy stop at the
    /// first character it cannot use and hand back what it read. That is the failure this crossing
    /// exists to prevent, one step further in: a collar typed as `2 5` would be stored as 2 kg, the
    /// confirming command would stay lit, and nothing on screen would say a number had been
    /// truncated. Matching the *whole* string refuses instead, which the user recovers from in a
    /// keystroke.
    ///
    /// Reading it in the user's locale is the other half: `102.5` typed where the decimal is written
    /// as a comma is not a number, and a lifter in such a locale cannot enter a half-kilo any other
    /// way. Grouping separators parse, because they are the locale's own; they are never written
    /// back out. See ``render(_:locale:)``.
    ///
    /// - Parameters:
    ///   - text: What is in the field.
    ///   - locale: The locale to read it in.
    /// - Returns: The value, or `nil` if the field is empty or is not, in whole, a number in that
    ///   locale.
    public static func decimal(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard
            let match = trimmed.wholeMatch(of: FloatingPointFormatStyle<Double>.number.locale(locale)),
            match.output.isFinite
        else {
            return nil
        }
        return match.output
    }

    /// Writes a value back into a field, in the user's locale.
    ///
    /// **No grouping separator**, deliberately: the field is re-parsed on the next keystroke, and a
    /// separator that a locale writes as a decimal point elsewhere is a value the user cannot then
    /// edit by hand. At most three decimals, which is a gram in kilograms and finer than any step a
    /// ± control takes.
    ///
    /// - Parameters:
    ///   - value: The number to write.
    ///   - locale: The locale to write it in.
    /// - Returns: The field's new contents.
    public static func render(_ value: Double, locale: Locale) -> String {
        value.formatted(
            .number.grouping(.never).precision(.fractionLength(0...3)).locale(locale)
        )
    }

    /// A mass the user typed, read in the unit they enter weights in (`G-3.1`, `G-3.2`).
    ///
    /// Rounded to the nearest gram, which is the only rounding this crossing performs: `G-3.3`'s
    /// display step governs a ± control, not what a typed number is allowed to be. A user who types
    /// 102.3 kg gets 102.3 kg.
    ///
    /// **Refused below zero, which `Weight` itself deliberately does not do.** That type is signed
    /// because it doubles as a delta — an increment, a deload — and says outright that a mass being
    /// non-negative is the caller's invariant. Every field in this module is that caller, and this
    /// is what stands between a pasted minus sign and a negative bar.
    ///
    /// - Parameters:
    ///   - text: What is in the field.
    ///   - unit: The unit the number is entered in.
    ///   - locale: The locale to read it in.
    /// - Returns: The mass, or `nil` when the field is empty, is not a number, or is negative.
    public static func weight(_ text: String, in unit: MassUnit, locale: Locale) -> Weight? {
        guard let entered = decimal(text, locale: locale), entered >= 0 else { return nil }
        return mass(entered, in: unit)
    }

    /// Writes a mass into a field, at the fewest decimals that still name it exactly.
    ///
    /// **Not ``render(_:locale:)`` over a converted `Double`, and the difference is visible on every
    /// pound gym.** A 45 lb bar is 20 412 g, and 20 412 g back in pounds is 45.00076…, so a fixed
    /// three decimals fills the field with `45.001` — a number the user did not type, in a form they
    /// are about to save. Grams are what is stored (`G-1.1`), so what a field wants is the shortest
    /// decimal that reads back as the same gram: `45`, `102.5`, `1.25`, and `102.375` where the user
    /// really did type it.
    ///
    /// Falls back to three decimals when no width round-trips, which is what a mass entered in a
    /// unit it cannot be written in exactly would do.
    ///
    /// - Parameters:
    ///   - weight: The mass to write. May be negative — assisted work is a real load (`G-1.6`).
    ///   - unit: The unit to write it in (`G-3.1`).
    ///   - locale: The locale to write it in (`G-3.4`).
    /// - Returns: The field's contents.
    public static func render(_ weight: Weight, in unit: MassUnit, locale: Locale) -> String {
        let converted = weight.converted(to: unit)
        for digits in 0...3 {
            let text = converted.formatted(
                .number.grouping(.never).precision(.fractionLength(digits)).locale(locale))
            if grams(text, in: unit, locale: locale) == weight.grams { return text }
        }
        return render(converted, locale: locale)
    }

    /// What a field's contents come to in grams, sign and all.
    ///
    /// - Parameters:
    ///   - text: What is in the field.
    ///   - unit: The unit it is entered in.
    ///   - locale: The locale to read it in.
    /// - Returns: The mass in grams, or `nil` when the field does not hold a number this unit can
    ///   express.
    private static func grams(_ text: String, in unit: MassUnit, locale: Locale) -> Int? {
        decimal(text, locale: locale).flatMap { mass($0, in: unit)?.grams }
    }

    /// One entered number as a mass, rounded to the nearest gram.
    ///
    /// - Parameters:
    ///   - entered: The number, in `unit`.
    ///   - unit: What it is a number of.
    /// - Returns: The mass, or `nil` for a number too large to hold in grams.
    private static func mass(_ entered: Double, in unit: MassUnit) -> Weight? {
        switch unit {
        case .kilograms: Weight(kilograms: entered, rounding: .nearest)
        case .pounds: Weight(pounds: entered, rounding: .nearest)
        }
    }

    /// A whole count the user typed — repetitions, or how many pairs of a plate.
    ///
    /// **The ceiling is `Int(exactly:)` rather than a comparison, and the difference is a crash.**
    /// `Double(Int.max)` is not `Int.max`: it rounds up to 2⁶³, so a guard reading
    /// `entered <= Double(Int.max)` admits the one value whose conversion then traps. Nineteen
    /// digits is a reachable thing to type into a number pad, and a field is re-read on every
    /// keystroke.
    ///
    /// - Parameters:
    ///   - text: What is in the field.
    ///   - locale: The locale to read it in.
    /// - Returns: The count, or `nil` when the field is empty, unparseable, fractional or negative.
    public static func count(_ text: String, locale: Locale) -> Int? {
        guard let entered = decimal(text, locale: locale) else { return nil }
        guard entered >= 0, entered == entered.rounded(.down), let count = Int(exactly: entered)
        else {
            return nil
        }
        return count
    }
}
