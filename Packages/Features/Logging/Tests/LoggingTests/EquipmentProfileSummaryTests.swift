import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// What a gym reads as in a list (`FR-1.4.3`, `FR-1.10.3`) — the other end of the collar convention,
/// and the two stand-ins a row can need.
@Suite("Equipment profile summary")
struct EquipmentProfileSummaryTests {
    /// The locale every line here is rendered in.
    private static let locale = Locale(identifier: "en_US_POSIX")

    @Test("The collar is shown as one collar, matching the field that wrote it")
    func collarIsShownAsOne() {
        // TR-0.3.7's trap from the display end: a row that drew the pair would hide the same
        // factor-of-two error the editor's label exists to prevent.
        let line = String(
            localized: EquipmentProfileSummary.bar(
                of: Self.profile(bar: 20_000, collar: 2_500, plates: [], pairs: []),
                unit: .kilograms,
                locale: Self.locale
            ))

        // The whole line rather than a substring: "2.5 kg" contains "5 kg", so a negative assertion
        // on the pair reading passes on the correct answer too.
        #expect(line == "Bar 20 kg, collars 2.5 kg each")
        // And the pair reading is a different line, which is what makes the one above falsifiable.
        #expect(
            String(
                localized: EquipmentProfileSummary.bar(
                    of: Self.profile(bar: 20_000, collar: 5_000, plates: [], pairs: []),
                    unit: .kilograms,
                    locale: Self.locale
                )) == "Bar 20 kg, collars 5 kg each")
    }

    @Test("Plates are listed at their own denomination, not at the display step")
    func platesKeepTheirDenomination() {
        let line = EquipmentProfileSummary.plates(
            of: Self.profile(
                bar: 20_000, collar: 0, plates: [25_000, 1_250], pairs: [4, 1]),
            unit: .kilograms,
            locale: Self.locale
        )

        // 1.25 kg is not representable at `G-3.3`'s half-kilogram step, and rounding it to 1.5 kg
        // would print a plate the gym does not have.
        #expect(line.contains("1.25 kg"))
        #expect(line.contains("25 kg"))
        // The plural agrees with the count, which is why this string lives in the `.stringsdict`:
        // four pairs of 25s and one pair of 1.25s.
        #expect(line.contains("25 kg × 4 pairs"))
        #expect(line.contains("1.25 kg × 1 pair"))
        #expect(!line.contains("1 pairs"))
    }

    @Test("A gym that stocks nothing says so rather than showing a blank")
    func noPlatesIsAnAnswer() {
        #expect(
            EquipmentProfileSummary.plates(
                of: Self.profile(bar: 20_000, collar: 0, plates: [], pairs: []),
                unit: .kilograms,
                locale: Self.locale
            ) == String(localized: LoggingStrings.equipmentNoPlates))
    }

    @Test("A row whose plate lists disagree is still listed")
    func aMalformedRowStillDraws() {
        // It is the one screen that can repair such a row, so refusing to draw it would strand it.
        let line = EquipmentProfileSummary.plates(
            of: Self.profile(bar: 20_000, collar: 0, plates: [25_000, 20_000], pairs: [1]),
            unit: .kilograms,
            locale: Self.locale
        )

        #expect(line.contains("25 kg"))
        #expect(!line.isEmpty)
    }

    @Test("A gym is called what the user called it, or named as unnamed")
    func namesMatchTheCalculator() {
        #expect(
            EquipmentProfileSummary.name(
                of: Self.profile(bar: 20_000, collar: 0, plates: [], pairs: [])) == "Home gym")
        #expect(
            EquipmentProfileSummary.name(
                of: Self.profile(bar: 20_000, collar: 0, plates: [], pairs: [], name: ""))
                == String(localized: LoggingStrings.plateEquipmentUnnamed))
    }

    /// A profile record, with only the fields these cases vary.
    private static func profile(
        bar: Int,
        collar: Int,
        plates: [Int],
        pairs: [Int],
        name: String = "Home gym"
    ) -> EquipmentProfile {
        EquipmentProfile(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            name: name,
            barWeight: Weight(grams: bar),
            collarWeight: Weight(grams: collar),
            plates: plates.map(Weight.init(grams:)),
            platePairCounts: pairs,
            isDefault: false
        )
    }
}
