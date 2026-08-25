import Foundation
import PowerliftingCore

/// An optional field's three answers: left empty, filled in, or filled in with something that is not
/// a value.
///
/// **Three, because two lose the case that matters.** An optional carrying `nil` cannot tell "the
/// user skipped RPE" from "the user typed *hard*" — and those are opposite: the first is a set that
/// logs, the second is a set that must not, because logging it would silently discard what was
/// typed.
enum OptionalField<Value: Equatable>: Equatable {
    /// The field was left empty. The set logs without it.
    case absent

    /// The field holds a value.
    case value(Value)

    /// The field holds something that is not one. The set does not log.
    case invalid
}

/// What the set editor holds while a set is being filled in, and what it refuses (`FR-1.2.3`).
///
/// **Text, not numbers, and that is `Weight`'s failable initializer meeting a keyboard.** A
/// `TextField` bound to a `Double` reverts what the user is halfway through typing — "10" on the way
/// to "102.5" is a complete number, and a lone "." is not one at all — so the fields here are
/// `String` and the crossing into `Weight` happens once, on confirm. That crossing is the only place
/// floating point exists in the logging path (`G-1.1`): a parsed decimal becomes grams immediately
/// and nothing downstream sees the `Double`.
///
/// **Both numeric fields are parsed against an explicit locale** (`G-3.4`). `Double("102,5")` is
/// `nil` in every locale that writes it that way, and a user in one of them cannot enter a
/// half-kilo.
///
/// **The unit is the user's display preference, not a constant** (`G-3.1`, `G-3.2`): the number
/// typed here means kilograms or pounds depending on a settings row, and reading it as the wrong one
/// stores a workout half again as heavy as it was.
///
/// **This is where an RPE is range-checked, and it is the only place that can be.**
/// `RepositoryInterface`'s `SetEntry` stores the column unvalidated on purpose — a foreign row
/// carrying 47 must survive a read — and `PowerliftingCore`'s `SetRecord` validates but is not what
/// a form binds to. The user's own keystrokes are the one source where an out-of-range value is a
/// typo rather than data to preserve.
struct SetDraft: Equatable, Sendable {
    /// The unit ``weightText`` is read in — the user's display preference.
    let unit: MassUnit

    /// The locale both numeric fields are parsed and rendered against.
    let locale: Locale

    /// The load, as typed.
    var weightText: String = ""

    /// The repetitions, as typed.
    var repsText: String = ""

    /// The RPE, as typed. Optional (`FR-1.2.3`), so an empty field is a set that logs.
    var rpeText: String = ""

    /// The per-set note (`FR-1.2.3`). Optional, and never refuses a set.
    var notes: String = ""

    /// Whether the set being drafted is a warmup rather than working (`FR-1.2.4`).
    ///
    /// **Working by default, and that default is decided here rather than inherited.** `G-1.8`
    /// forbids `SetEntry` from defaulting either flag, so somebody has to choose; a form that opened
    /// on *warmup* would put the day's work into the sequence that `FR-1.6`'s calculator ignores,
    /// which is the expensive direction of the two to get wrong.
    ///
    /// **Not part of ``isBlank``.** The other four fields can be empty and this one cannot — a
    /// boolean always holds a value — so counting it would make every draft non-blank and the form
    /// would open complaining about fields nobody has touched yet.
    var isWarmup: Bool = false

    /// The modifiers applied to the set (`FR-1.2.8`) — none, one, or several.
    ///
    /// **`SetModifier` rather than `SetModifierTerm`, so a spelling this build does not recognise
    /// survives the form.** A set edited here can carry a term written by a newer version or one the
    /// user has since removed from their list; held as the enum it would arrive as `nil` and the
    /// next confirm would delete it. See ``SetModifierVocabulary``.
    ///
    /// **Order is not meaningful and is not preserved past this type**: the storage layer sorts by
    /// spelling and deduplicates. Kept as written here only so a row the user just tapped does not
    /// jump.
    var modifiers: [SetModifier] = []

    /// The scale RPE is entered on. Outside it, the field is a typo rather than a rating.
    static let rpeRange: ClosedRange<Double> = 1...10

    /// An empty draft in the given unit.
    ///
    /// - Parameters:
    ///   - unit: The unit the load is entered in.
    ///   - locale: The locale the numbers are read in.
    init(unit: MassUnit, locale: Locale) {
        self.unit = unit
        self.locale = locale
    }

    /// A draft carrying `set`'s load, reps, RPE and kind — `FR-1.2.6`'s duplicate.
    ///
    /// **The note is deliberately not carried.** Weight, reps and RPE describe how the set was
    /// performed and repeat by default; a note says something about one set — "left knee", "belt on
    /// the last two" — and repeating it would put words in the user's mouth on every subsequent set.
    ///
    /// **The modifiers are carried too**, on the same argument: a belt is on for the whole top set
    /// and knee wraps do not come off between attempts, so a duplicate that dropped them would cost
    /// a tap per set to put back — and, unlike the note, a modifier describes the effort rather than
    /// the occasion.
    ///
    /// **The warmup flag *is* carried**, and it is the one field where repeating matters most: a
    /// ramp is three or four warmups in a row, each one a repeat of the last with the load moved, so
    /// a duplicate that came back as a working set would put every rung of the ramp into the work
    /// and cost `NFR-1.3`'s three taps a fourth to undo it each time.
    ///
    /// - Parameters:
    ///   - set: The set to repeat.
    ///   - unit: The unit to render its load in.
    ///   - locale: The locale to render the numbers in.
    init(repeating set: SetEntryValues, unit: MassUnit, locale: Locale) {
        self.init(unit: unit, locale: locale)
        weightText = Self.render(set.weight.converted(to: unit), locale: locale)
        repsText = Self.render(Double(set.reps), locale: locale)
        if let rpe = set.rpe {
            rpeText = Self.render(rpe, locale: locale)
        }
        isWarmup = set.isWarmup
        modifiers = set.modifiers
    }

    /// A draft carrying everything `set` records — `FR-1.2.7`'s edit.
    ///
    /// **The note comes across, and that is the whole difference from
    /// ``init(repeating:unit:locale:)``.** A duplicate drops it because repeating a note puts words
    /// in the user's mouth on a set they have not performed yet; an edit is the *same* set, and a
    /// form that opened with the note missing would delete it on the next confirm.
    ///
    /// - Parameters:
    ///   - set: The set being edited.
    ///   - unit: The unit to render its load in.
    ///   - locale: The locale to render the numbers in.
    init(editing set: SetEntryValues, unit: MassUnit, locale: Locale) {
        self.init(repeating: set, unit: unit, locale: locale)
        notes = set.notes
    }
}

// MARK: - What the draft resolves to

extension SetDraft {
    /// The load, or `nil` when the field is empty, holds something that is not a number, or is
    /// negative.
    ///
    /// Rounded to the nearest gram, which is the only rounding this crossing performs: `G-3.3`'s
    /// display step governs the ± controls, not what a typed number is allowed to be. A user who
    /// types 102.3 kg gets 102.3 kg.
    ///
    /// **Refused below zero, which `Weight` itself deliberately does not do.** That type is signed
    /// because it doubles as a delta — an increment, a deload — and says outright that a load being
    /// non-negative is the caller's invariant. This crossing is that caller, and it is the only one
    /// standing between a pasted minus sign and a negative load in `FR-1.6`'s calculator. The ±
    /// controls already floor at zero; the field is what was left.
    var weight: Weight? {
        guard let entered = Self.decimal(weightText, locale: locale), entered >= 0 else {
            return nil
        }
        switch unit {
        case .kilograms: return Weight(kilograms: entered, rounding: .nearest)
        case .pounds: return Weight(pounds: entered, rounding: .nearest)
        }
    }

    /// The repetitions, or `nil` when the field is empty, unparseable, fractional or negative.
    ///
    /// **Zero is a value here, not an absence** — `FR-1.2.5`'s failed set records zero reps, so a
    /// guard that demanded one would refuse exactly the set the requirement names.
    ///
    /// **The ceiling is `Int(exactly:)` rather than a comparison, and the difference is a crash.**
    /// `Double(Int.max)` is not `Int.max`: it rounds up to 2⁶³, so a guard reading
    /// `entered <= Double(Int.max)` admits the one value whose conversion then traps. Nineteen
    /// digits is a reachable thing to type into a number pad, and this property is recomputed on
    /// every keystroke.
    var reps: Int? {
        guard let entered = Self.decimal(repsText, locale: locale) else { return nil }
        guard entered >= 0, entered == entered.rounded(.down), let count = Int(exactly: entered)
        else {
            return nil
        }
        return count
    }

    /// The RPE, whether it was skipped, or whether what is there is not one.
    var rpe: OptionalField<Double> {
        if rpeText.trimmingCharacters(in: .whitespaces).isEmpty { return .absent }
        guard let entered = Self.decimal(rpeText, locale: locale),
            Self.rpeRange.contains(entered)
        else {
            return .invalid
        }
        return .value(entered)
    }

    /// Whether this draft can be logged — every required field parses, and no optional one is wrong.
    var isLoggable: Bool {
        weight != nil && reps != nil && rpe != .invalid
    }

    /// Whether nothing has been entered — every field empty and no modifier picked.
    ///
    /// **The modifiers count where ``isWarmup`` does not**, and the difference is that a list can be
    /// empty where a boolean cannot: counting the flag would make every draft non-blank, and *not*
    /// counting the modifiers would leave a form the user has only picked a modifier on reading as
    /// untouched.
    ///
    /// **Not the negation of ``isLoggable``, and reading it as one hides a refusal.** A form nobody
    /// has filled in and a form filled in wrongly are opposite situations: the first has nothing to
    /// complain about, the second has to say why the confirming command will not go. A draft opened
    /// as `FR-1.2.6`'s duplicate is never blank — so a repeat of a set whose stored rating is
    /// outside `1...10`, which a stored row is deliberately allowed to be, explains itself instead
    /// of opening on a dead button.
    var isBlank: Bool {
        modifiers.isEmpty
            && [weightText, repsText, rpeText, notes].allSatisfy {
                $0.trimmingCharacters(in: .whitespaces).isEmpty
            }
    }

    /// The RPE to store, once ``isLoggable`` is known to hold.
    var storedRPE: Double? {
        if case .value(let rating) = rpe { return rating }
        return nil
    }
}

// MARK: - The ± controls

extension SetDraft {
    /// How far one tap of the load's ± controls moves it, in the display unit.
    ///
    /// `G-3.3`'s default step for the unit — half a kilo, or a whole pound — so the increment
    /// matches the plates that exist rather than a round number of grams.
    var weightStep: Double {
        Double(DisplayPrecision.default(for: unit).milliUnits) / 1000
    }

    /// This draft with its load moved `steps` steps, floored at zero.
    ///
    /// **The arithmetic stays in the display unit rather than going through `Weight`.** A pound
    /// value round-tripped through grams comes back as 220.46226…, and a text field the user is
    /// about to type into must not fill itself with that.
    ///
    /// An empty or unparseable field counts as zero, so the first tap of **+** on a blank draft is
    /// one step rather than nothing.
    ///
    /// - Parameter steps: How many steps to move — negative is down.
    /// - Returns: The adjusted draft.
    func adjustingWeight(by steps: Int) -> SetDraft {
        let current = Self.decimal(weightText, locale: locale) ?? 0
        let moved = max(0, current + Double(steps) * weightStep)
        var adjusted = self
        adjusted.weightText = Self.render(moved, locale: locale)
        return adjusted
    }

    /// This draft with its repetitions moved by `steps`, floored at zero. See
    /// ``adjustingWeight(by:)``.
    ///
    /// - Parameter steps: How many repetitions to move — negative is down.
    /// - Returns: The adjusted draft.
    func adjustingReps(by steps: Int) -> SetDraft {
        let current = reps ?? 0
        var adjusted = self
        adjusted.repsText = Self.render(Double(max(0, current + steps)), locale: locale)
        return adjusted
    }
}

// MARK: - Crossing between text and numbers

extension SetDraft {
    /// Reads a decimal the user typed, in their locale.
    ///
    /// **Strict, and that is measured rather than cautious.** Lenient parsing — the default —
    /// consumes the leading part of a field it cannot finish, so `102.5` typed in a locale that
    /// writes the decimal as a comma resolves to **102**, and the set is logged half a kilo light
    /// with nothing on screen saying so. Observed in the simulator, whose locale writes the comma.
    /// Refused instead, the confirming command stays disabled and the message beside it says what
    /// the field wants — a set that will not log is recoverable, and a set logged wrong is not.
    ///
    /// Grouping separators still parse, because they are the locale's own and a strict read accepts
    /// what the locale writes; they are never written back out. See ``render(_:locale:)``.
    ///
    /// - Parameters:
    ///   - text: What is in the field.
    ///   - locale: The locale to read it in.
    /// - Returns: The value, or `nil` if the field is empty or is not a number in that locale.
    private static func decimal(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard
            let value = try? Double(trimmed, format: .number.locale(locale), lenient: false),
            value.isFinite
        else {
            return nil
        }
        return value
    }

    /// Writes a value back into a field, in the user's locale.
    ///
    /// **No grouping separator**, deliberately: the field is re-parsed on the next keystroke, and a
    /// separator that a locale writes as a decimal point elsewhere is a value the user cannot then
    /// edit by hand. At most three decimals, which is a gram in kilograms and finer than any step
    /// the ± controls take.
    ///
    /// - Parameters:
    ///   - value: The number to write.
    ///   - locale: The locale to write it in.
    /// - Returns: The field's new contents.
    private static func render(_ value: Double, locale: Locale) -> String {
        value.formatted(
            .number.grouping(.never).precision(.fractionLength(0...3)).locale(locale)
        )
    }
}

/// What one logged set records, apart from where it sits — the six fields the editor collects and
/// the store writes (`FR-1.2.3`, `FR-1.2.4`, `FR-1.2.8`).
///
/// **A value rather than `SetEntry` itself**, so a draft can be built in a test — and in a preview —
/// without a stored row behind it, and so the store's command takes one argument rather than five.
///
/// **`FR-1.2.6`'s duplicate carries five of the six and deliberately drops ``notes``** — which is
/// the duplicate's decision rather than this type's, and is argued at the initialiser that makes
/// one.
public struct SetEntryValues: Equatable, Sendable {
    /// The load on one implement.
    public let weight: Weight

    /// The repetitions performed. Zero is `FR-1.2.5`'s failed set.
    public let reps: Int

    /// The rating, where the set carried one.
    public let rpe: Double?

    /// Whether it was a warmup rather than working (`FR-1.2.4`).
    public let isWarmup: Bool

    /// The modifiers the set was performed under (`FR-1.2.8`), or none.
    ///
    /// Passed through as written; the storage layer is what deduplicates and sorts it.
    public let modifiers: [SetModifier]

    /// The per-set note, or empty (`FR-1.2.3`).
    public let notes: String

    /// Builds the value.
    ///
    /// - Parameters:
    ///   - weight: The load on one implement.
    ///   - reps: The repetitions performed.
    ///   - rpe: The rating, where there is one.
    ///   - isWarmup: Whether it is a warmup.
    ///   - modifiers: The modifiers applied, or none.
    ///   - notes: The per-set note, or empty.
    public init(
        weight: Weight,
        reps: Int,
        rpe: Double?,
        isWarmup: Bool,
        modifiers: [SetModifier] = [],
        notes: String = ""
    ) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.modifiers = modifiers
        self.notes = notes
    }
}
