import Testing

@testable import PowerliftingCore

// Placeholder suite (T-0.04). PowerliftingCore declares no API yet, so there is nothing here
// worth asserting — this exists only to prove the harness runs and that coverage collection
// produces a number. Delete this file once T-0.10 lands `Weight`; the real formula suites
// (G-6.2) arrive with T-0.14 onwards.
//
// Kept deliberately free of Foundation: a test target that imports an Apple framework would
// still compile on Darwin but break the Linux job (T-0.08), which runs this suite too.
@Suite("PowerliftingCore harness")
struct SuiteSmokeTests {
    @Test("The module is importable and the test harness runs")
    func moduleIsImportable() {
        #expect(Bool(true))
    }
}
