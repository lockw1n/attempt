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

    @Test(
        "A plate below the quarter floor is drawn as something rather than as nothing",
        arguments: [
            // The defect this exists for: anchored at the floor, a 100 g plate rounds to zero
            // there, every coarser step agrees with that zero, and the coarsest-matching rule
            // printed `0 kg × 1` as the instruction for what to put on the bar.
            (100, "0.1 kg"),
            (124, "0.1 kg"),
            (40, "0.04 kg"),
            (1, "0.001 kg"),
        ])
    func denominationsBelowTheFloor(grams: Int, drawn: String) {
        let line = PlateLoadingSummary.perSide(
            PlateLoading(
                totalWeight: Weight(grams: 25_000 + 2 * grams),
                perSide: [PlateCount(plate: Weight(grams: grams), count: 1)]),
            unit: .kilograms,
            locale: Self.english
        )
        #expect(line == "\(drawn) × 1")
        // Anchored to the literal as well as to the whole line: the failure this guards is a
        // number that renders as zero, which no equality against another rendering would catch.
        #expect(!line.hasPrefix("0 kg"))
    }

    @Test("The floor itself still answers at the quarter, and zero is still zero")
    func theFloorIsUnmoved() {
        #expect(PlateLoadingSummary.step(for: Weight(grams: 125), in: .kilograms) == .quarter)
        #expect(PlateLoadingSummary.step(for: Weight(grams: 0), in: .kilograms) == .whole)
        #expect(
            PlateLoadingSummary.render(Weight(grams: 0), in: .kilograms, locale: Self.english)
                == "0 kg")
    }

    @Test("A load keeps G-3.3's display step, where a denomination does not")
    func loadsAreDrawnAtTheDisplayStep() {
        // The two sit one under the other as FR-1.4.4's pair, which is the column a fixed fraction
        // width exists for: at the denomination step they would read `100 kg` over `102.5 kg`.
        #expect(
            PlateLoadingSummary.load(Weight(grams: 100_000), in: .kilograms, locale: Self.english)
                == "100.0 kg")
        #expect(
            PlateLoadingSummary.load(Weight(grams: 102_500), in: .kilograms, locale: Self.english)
                == "102.5 kg")
        // The same weight as a plate, which is what makes the split visible.
        #expect(
            PlateLoadingSummary.render(Weight(grams: 100_000), in: .kilograms, locale: Self.english)
                == "100 kg")
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
