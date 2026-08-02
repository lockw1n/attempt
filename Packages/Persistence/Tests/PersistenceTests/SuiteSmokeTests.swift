import Testing

@testable import Persistence

// Placeholder suite (T-0.04). Persistence declares no entities yet. Delete this file once
// T-0.30 lands the entity conventions and T-0.31/T-0.32 the models.
@Suite("Persistence harness")
struct SuiteSmokeTests {
    @Test("The module is importable and the test harness runs")
    func moduleIsImportable() {
        #expect(Bool(true))
    }
}
