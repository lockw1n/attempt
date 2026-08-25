import Foundation

/// ``LoggingStrings``' third file — `FR-1.4.1`'s plate calculator, reached from the set editor.
///
/// **The same type in a third file, on `LoggingModifierStrings.swift`'s argument**: one enum is what
/// keeps a module's copy in one place, and `file_length` is what keeps that one place readable.
extension LoggingStrings {
    // MARK: - Plate calculator (FR-1.4.1, FR-1.4.4)

    /// The set editor's row into the calculator, and the calculator's own title — one string drawn
    /// in two places, unlike this file's usual rule, because here it is the same object named twice:
    /// the row is the screen's summary and the screen is the row expanded.
    static let plateRowLabel = resource("logging.session.plate.row.label")

    /// The row's line before the equipment has been read, and after a read that failed.
    ///
    /// It names the tap rather than the wait: the tap is what resolves either case, and a row that
    /// said "loading" would still say it over a read that is never coming back.
    static let plateRowUnknown = resource("logging.session.plate.row.unknown")

    /// The row's line for a weight that will not go on the bar (`FR-1.4.4`). The two nearest
    /// weights are the screen's, not the row's.
    static let plateRowNotLoadable = resource("logging.session.plate.row.not-loadable")

    /// The calculator's title.
    static let plateTitle = resource("logging.session.plate.title")

    /// The way out of it.
    static let plateDoneAction = resource("logging.session.plate.done.action")

    /// The label over the weight being loaded for.
    static let plateTargetLabel = resource("logging.session.plate.target.label")

    /// The heading over a target that loads exactly (`FR-1.4.1`).
    static let plateExactSection = resource("logging.session.plate.exact.section")

    /// The heading over the heaviest loading under the target (`FR-1.4.4`).
    static let plateBelowSection = resource("logging.session.plate.below.section")

    /// The heading over the lightest loading over it (`FR-1.4.4`).
    static let plateAboveSection = resource("logging.session.plate.above.section")

    /// Why there is nothing below: the bar and its collars already weigh more than the target.
    static let plateBelowNoneHeadline = resource("logging.session.plate.below.none.headline")

    /// What that means, in `FR-1.13.3`'s concrete terms.
    static let plateBelowNoneMessage = resource("logging.session.plate.below.none.message")

    /// Why there is nothing above: the gym's plates do not reach the target.
    static let plateAboveNoneHeadline = resource("logging.session.plate.above.none.headline")

    /// What would change it — heavier pairs on the profile (`FR-1.4.2`).
    static let plateAboveNoneMessage = resource("logging.session.plate.above.none.message")

    /// A loading that carries no plates. **Not an empty string**: a bare bar is an answer.
    static let plateBareBar = resource("logging.session.plate.bare-bar")

    /// The label over the plate list, which is per side and says so (`FR-1.4.1`).
    static let platePerSideLabel = resource("logging.session.plate.per-side.label")

    /// The heading over which gym the loading was computed on.
    static let plateEquipmentSection = resource("logging.session.plate.equipment.section")

    /// What the interim default is called, since it is not a gym the user named (`G-6.2`).
    static let plateEquipmentInterim = resource("logging.session.plate.equipment.interim")

    /// The heading when the equipment could not be read.
    static let plateErrorHeadline = resource("logging.session.plate.error.headline")

    /// What that costs the screen, and what a retry would do.
    static let plateErrorMessage = resource("logging.session.plate.error.message")

    /// The heading when a profile was read and cannot describe a gym.
    static let plateUnusableHeadline = resource("logging.session.plate.unusable.headline")

    /// What would fix it. No retry is offered — see the screen.
    static let plateUnusableMessage = resource("logging.session.plate.unusable.message")

    /// The bar and the collars a loading assumed.
    ///
    /// **Both already rendered** — `AppFormat` decides how a weight reads, and a catalogue that took
    /// two `Weight`s could not (`G-3.4`).
    ///
    /// - Parameters:
    ///   - bar: The bar's mass, formatted.
    ///   - collar: The mass of one collar, formatted.
    /// - Returns: The line.
    static func plateEquipmentBar(bar: String, collar: String) -> LocalizedStringResource {
        resource("logging.session.plate.equipment.bar \(bar) \(collar)")
    }

    /// One denomination on one side: the plate, then how many of it.
    ///
    /// The multiplication sign is a **character** here rather than the drawn glyph a set row hides,
    /// so VoiceOver announces it as a word — `PreviousPerformanceStrip`'s rule.
    ///
    /// - Parameters:
    ///   - plate: The plate's mass, formatted.
    ///   - count: How many go on each side, formatted.
    /// - Returns: The item.
    static func plateCount(plate: String, count: String) -> LocalizedStringResource {
        resource("logging.session.plate.count \(plate) \(count)")
    }

    /// The plate calculator's copy, for ``LoggingStrings/all``.
    static var allPlateStrings: [LocalizedStringResource] {
        [
            plateRowLabel, plateRowUnknown, plateRowNotLoadable, plateTitle, plateDoneAction,
            plateTargetLabel, plateExactSection, plateBelowSection, plateAboveSection,
            plateBelowNoneHeadline, plateBelowNoneMessage, plateAboveNoneHeadline,
            plateAboveNoneMessage, plateBareBar, platePerSideLabel, plateEquipmentSection,
            plateEquipmentInterim, plateErrorHeadline, plateErrorMessage, plateUnusableHeadline,
            plateUnusableMessage, plateEquipmentBar(bar: "", collar: ""),
            plateCount(plate: "", count: ""),
        ]
    }
}
