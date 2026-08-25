import Foundation
import PowerliftingCore
import Testing

@testable import Logging

/// What a loading says (`FR-1.4.1`) — the line the set editor's row draws and the calculator repeats
/// under each of `FR-1.4.4`'s two weights.
@Suite("Plate loading copy")
struct PlateLoadingSummaryTests {
    private static let english = Locale(identifier: "en_US")

    @Test("A bar carrying no plates says so rather than saying nothing")
    func bareBarIsAnAnswer() {
        let bare = PlateLoading(totalWeight: Weight(grams: 25_000), perSide: [])
        #expect(
            PlateLoadingSummary.perSide(bare, unit: .kilograms, locale: Self.english)
                == "Bar and collars only")
    }

    @Test("Each denomination is drawn with how many go on a side")
    func denominationsAndCounts() {
        let loading = PlateLoading(
            totalWeight: Weight(grams: 165_000),
            perSide: [
                PlateCount(plate: Weight(grams: 25_000), count: 2),
                PlateCount(plate: Weight(grams: 20_000), count: 1),
            ])
        #expect(
            PlateLoadingSummary.perSide(loading, unit: .kilograms, locale: Self.english)
                == "25 kg × 2, 20 kg × 1")
    }

    @Test("A plate the display step cannot represent is drawn at the finer step, not rounded")
    func fractionalPlatesAreNotRounded() {
        // The defect this exists for: at `G-3.3`'s half-kilogram, 1.25 kg reads as `1.5 kg` — a
        // plate the gym does not own, printed as the instruction for what to load.
        let loading = PlateLoading(
            totalWeight: Weight(grams: 27_500),
            perSide: [PlateCount(plate: Weight(grams: 1_250), count: 1)])
        let line = PlateLoadingSummary.perSide(loading, unit: .kilograms, locale: Self.english)
        #expect(line == "1.25 kg × 1")
        #expect(!line.contains("1.5"))
    }

    @Test("The coarsest step that leaves the number alone is the one used")
    func coarseStepWhereItFits() {
        #expect(PlateLoadingSummary.step(for: Weight(grams: 20_000), in: .kilograms) == .whole)
        #expect(PlateLoadingSummary.step(for: Weight(grams: 2_500), in: .kilograms) == .half)
        #expect(PlateLoadingSummary.step(for: Weight(grams: 1_250), in: .kilograms) == .quarter)
        #expect(PlateLoadingSummary.step(for: Weight(grams: 102_500), in: .kilograms) == .half)
    }

    @Test("The editor's row shows the plates for a target that loads")
    func rowForAnExactTarget() {
        let loading = PlateLoading(
            totalWeight: Weight(grams: 65_000),
            perSide: [PlateCount(plate: Weight(grams: 20_000), count: 1)])
        #expect(
            PlateLoadingSummary.row(.exact(loading), unit: .kilograms, locale: Self.english)
                == "20 kg × 1")
    }

    @Test("The editor's row refuses a target that does not, and leaves the pair to the screen")
    func rowForANonExactTarget() {
        let below = PlateLoading(totalWeight: Weight(grams: 100_000), perSide: [])
        #expect(
            PlateLoadingSummary.row(
                .nearest(below: below, above: nil), unit: .kilograms, locale: Self.english)
                == "Not exactly loadable")
    }
}
