import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// What the pipeline announces, and to whom (`TR-1.5`).
///
/// A file of its own rather than a `// MARK:` in ``PersonalRecordRecomputerTests``: that file had
/// reached SwiftLint's length ceiling, and publication is the section that shares least with the
/// rest. Its fixtures are the same target's.
@Suite("Personal record publication")
struct PersonalRecordPublicationTests {
    @Test("A recompute is announced to a subscriber")
    func aRecomputeIsPublished() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])
        var changes = await fixture.recomputer.changes().makeAsyncIterator()

        try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        #expect(await changes.next() == .exercise(fixture.exerciseID))
    }

    @Test("A formula change announces every exercise")
    func aFormulaChangeIsPublished() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])
        var changes = await fixture.recomputer.changes().makeAsyncIterator()

        await fixture.recomputer.formulaDidChange(to: .lombardi)

        #expect(await changes.next() == .everyExercise)
    }

    /// A redundant announcement makes every screen in the app walk its exercise's history for an
    /// answer that cannot have moved.
    @Test("Choosing the formula already in force announces nothing")
    func aRedundantFormulaChangeIsSilent() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])
        var changes = await fixture.recomputer.changes().makeAsyncIterator()

        await fixture.recomputer.formulaDidChange(to: .defaultFormula)
        try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        // The recompute's announcement is the first one to arrive, so the formula published none.
        #expect(await changes.next() == .exercise(fixture.exerciseID))
    }

    @Test("Every subscriber is told, not whichever was awaiting")
    func everySubscriberIsTold() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])
        var first = await fixture.recomputer.changes().makeAsyncIterator()
        var second = await fixture.recomputer.changes().makeAsyncIterator()

        try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        #expect(await first.next() == .exercise(fixture.exerciseID))
        #expect(await second.next() == .exercise(fixture.exerciseID))
    }
}
