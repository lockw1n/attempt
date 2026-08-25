import Foundation
import Localization
import PowerliftingCore

/// A loading, in words (`FR-1.4.1`).
///
/// **A type of its own rather than a method on the view**, for the reason every other formatting
/// helper in this module has one: what a per-side list says is a unit test's question, where what it
/// looks like is a snapshot's — and the same sentence is drawn twice, once inside the set editor's
/// row and once on the calculator itself.
///
/// **A locale-formatted list rather than a joined string** (`G-3.4`), on the modifiers row's rule:
/// the separator between two items is not a comma in every language. The **narrow** width is what
/// keeps it a sequence — four plates are four plates, not three plates *and* a fourth.
enum PlateLoadingSummary {
    /// What goes on one side of the bar, as one line.
    ///
    /// An empty list is **not** an empty string: a bar carrying nothing is a loading like any other
    /// (see ``PowerliftingCore/PlateLoading/perSide``), and rendering it blank would read as a
    /// failure to compute rather than as the answer it is.
    ///
    /// - Parameters:
    ///   - loading: The loaded bar.
    ///   - unit: The unit the plate masses are drawn in (`G-3.1`).
    ///   - locale: What the numbers and the list separator are rendered for (`G-3.4`).
    /// - Returns: The line.
    static func perSide(_ loading: PlateLoading, unit: MassUnit, locale: Locale) -> String {
        guard !loading.perSide.isEmpty else {
            return String(localized: LoggingStrings.plateBareBar)
        }
        return loading.perSide
            .map {
                String(
                    localized: LoggingStrings.plateCount(
                        plate: render($0.plate, in: unit, locale: locale),
                        count: $0.count.formatted(AppFormat.count(locale: locale))
                    ))
            }
            .formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    /// One weight, rendered at the finer of two steps where the coarser one would move it.
    ///
    /// **`G-3.3`'s display step is wrong on this screen, and it is wrong in the one way that
    /// matters.** That step is half a kilogram, so a 1.25 kg plate renders as `1.5 kg` — a
    /// denomination the gym does not stock, printed as the instruction for what to put on the bar.
    /// Every other surface in the app rounds a *logged* number for legibility; this one is asserting
    /// exact loadability, and a rounded plate contradicts the claim the whole screen makes.
    ///
    /// **The coarsest step that leaves the number alone is what is used**, which is also what makes
    /// a plate list read like one: `25 kg × 4, 20 kg × 1, 1.25 kg × 1`, each denomination at its own
    /// width. Elsewhere the app renders a *logged* load at one fixed step, `100.0 kg` included,
    /// because a column of numbers is scanned and a ragged fraction width is what makes it hard to;
    /// here the numbers are a list of distinct objects rather than a column, and a trailing zero on
    /// a plate is a decimal the plate does not have.
    ///
    /// A denomination finer than a quarter of the display unit — a 100 g micro-plate — is still
    /// rounded. `DisplayPrecision` has no step between a quarter and a thousandth, and a thousandth
    /// would render every plate to three decimals; `PlateInventory` accepts anything from a gram, so
    /// this is a real if exotic limit rather than an impossible one.
    ///
    /// - Parameters:
    ///   - weight: The mass to draw.
    ///   - unit: The unit to draw it in (`G-3.1`).
    ///   - locale: What to render it for (`G-3.4`).
    /// - Returns: The rendered weight, with its unit symbol.
    static func render(_ weight: Weight, in unit: MassUnit, locale: Locale) -> String {
        AppFormat.weight(in: unit, precision: step(for: weight, in: unit), locale: locale)
            .format(weight)
    }

    /// The coarsest step, down to a quarter unit, that leaves `weight` where it is.
    ///
    /// Decided by rendering at each and comparing the numbers, rather than by re-deriving the
    /// arithmetic: the domain type owns how a step is applied, and a second implementation here
    /// would disagree with it at the ties — `WeightStyle`'s own rule.
    ///
    /// - Parameters:
    ///   - weight: The mass to draw.
    ///   - unit: The unit to draw it in.
    /// - Returns: The step to draw it at.
    static func step(for weight: Weight, in unit: MassUnit) -> DisplayPrecision {
        // Coarsest first. The last is the floor: a denomination finer than it is rounded, which is
        // the limit named above.
        let steps: [DisplayPrecision] = [.whole, .half, .quarter]
        guard let exact = Double(weight.formatted(in: unit, precision: .quarter)) else {
            return .quarter
        }
        for step in steps where Double(weight.formatted(in: unit, precision: step)) == exact {
            return step
        }
        return .quarter
    }

    /// What the set editor's row says for a target, in one line.
    ///
    /// **A non-exact target gets a refusal here and its two nearest weights on the screen**, rather
    /// than both weights squeezed onto a form row. `FR-1.4.4` wants the pair *shown*, and a row that
    /// is already one line inside a sheet at `NFR-1.10`'s ceiling cannot show two weights and their
    /// plates; what it can do is say that the number the user typed will not go on the bar, which is
    /// the fact that sends them into the screen.
    ///
    /// - Parameters:
    ///   - result: What the target loaded to.
    ///   - unit: The unit the plate masses are drawn in.
    ///   - locale: What the line is rendered for.
    /// - Returns: The line.
    static func row(_ result: PlateLoadingResult, unit: MassUnit, locale: Locale) -> String {
        switch result {
        case .exact(let loading):
            return perSide(loading, unit: unit, locale: locale)
        case .nearest:
            return String(localized: LoggingStrings.plateRowNotLoadable)
        }
    }
}
