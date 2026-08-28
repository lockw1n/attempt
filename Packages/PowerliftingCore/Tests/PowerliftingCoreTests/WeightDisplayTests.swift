import Testing

@testable import PowerliftingCore

/// `G-3.1` and `G-3.3` travelling together: a step means half a *kilogram* or half a *pound*
/// depending on the unit beside it.
@Suite("WeightDisplay")
struct WeightDisplayTests {
    @Test("A pairing keeps both halves as given")
    func bothHalvesAreKept() {
        let display = WeightDisplay(unit: .pounds, precision: .quarter)

        #expect(display.unit == .pounds)
        #expect(display.precision == .quarter)
    }

    /// The factory step is not one number: 0.5 kg but 1 lb, which is why a row that has never been
    /// configured stores no step at all.
    @Test("A unit alone takes that unit's own step")
    func aUnitAloneTakesItsFactoryStep() {
        #expect(WeightDisplay(unit: .kilograms).precision == .half)
        #expect(WeightDisplay(unit: .pounds).precision == .whole)
    }

    @Test("An absent step resolves to the unit's own; a chosen one is kept")
    func resolvingAnAbsentStep() {
        #expect(WeightDisplay(unit: .pounds, resolving: nil).precision == .whole)
        #expect(WeightDisplay(unit: .pounds, resolving: .tenth).precision == .tenth)
    }

    @Test("The standard pairing is kilograms at half-kilogram steps")
    func theStandardPairing() {
        #expect(WeightDisplay.standard == WeightDisplay(unit: .kilograms, precision: .half))
        #expect(WeightDisplay.standard != WeightDisplay(unit: .pounds, precision: .half))
    }

    @Test("It crosses an isolation boundary")
    func isSendable() {
        requireSendable(WeightDisplay.self)
    }

    /// Compiles only for a `Sendable` type. See ``WeightTests``' own.
    private func requireSendable<T: Sendable>(_ type: T.Type) {}
}
