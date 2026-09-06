import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-16.6.5`'s self-fold: which exercise a card closes itself over, and which it does not.
///
/// The card reads ``SessionExercise/isDone`` for its fold (`SessionExerciseList`), so this is that
/// predicate rather than a rendering — what a folded card looks like is a snapshot's question.
@Suite("What folds an exercise card")
struct SessionSelfFoldTests {
    @Test("A plan with sets still to come keeps the card open, however well the logged ones went")
    func anUnexhaustedPlanKeepsItOpen() {
        // Three sets prescribed, one performed and completed. Every *logged* working set is
        // complete, which is the whole of Phase 1's rule — and folding here would hide the two sets
        // the routine still asks for at the moment the lifter is about to perform them.
        let card = PlanFixture.card(
            sets: [PlanFixture.workingSet(order: 0)],
            planned: [PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 3)]
        )
        #expect(card.nextPlannedGroup != nil)
        #expect(!card.isComplete)
        #expect(!card.isDone)
    }

    @Test("A plan worked through to its end folds the card")
    func anExhaustedPlanFolds() {
        let card = PlanFixture.card(
            sets: (0..<3).map { PlanFixture.workingSet(order: $0) },
            planned: [PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 3)]
        )
        #expect(card.nextPlannedGroup == nil)
        #expect(card.isComplete)
    }

    @Test("Every group of a multi-group plan has to be exhausted, not just the first")
    func everyGroupCounts() {
        // The top set is done and the backoff is not. `nextPlannedGroup` walks the groups rather
        // than indexing them, so this is the case that separates "the plan is finished" from "the
        // first thing in it is".
        let card = PlanFixture.card(
            sets: [PlanFixture.workingSet(order: 0, grams: 100_000)],
            planned: [
                PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 1),
                PlanFixture.group(order: 1, grams: 85_000, reps: 8, sets: 3),
            ]
        )
        #expect(!card.isComplete)
    }

    @Test("A pending set keeps the card open even where the plan is exhausted")
    func aPendingSetKeepsItOpen() {
        // `FR-16.4.1`: a set nobody attempted carries `isCompleted == false` inside an open workout,
        // and the fold's first clause is what refuses it. Asserted with the plan satisfied so the
        // new clause cannot be what is doing the work.
        let card = PlanFixture.card(
            sets: [
                PlanFixture.workingSet(order: 0),
                PlanFixture.workingSet(order: 1, isCompleted: false),
            ],
            planned: [PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 2)]
        )
        #expect(card.nextPlannedGroup == nil)
        #expect(!card.isComplete)
    }

    @Test("An exercise nobody planned folds on its sets alone, exactly as it did in Phase 1")
    func anUnplannedExerciseIsUnchanged() {
        let card = PlanFixture.card(
            sets: [PlanFixture.workingSet(order: 0), PlanFixture.workingSet(order: 1)], planned: [])
        #expect(card.isComplete)
    }

    @Test("Warming up does not consume a planned set, so it cannot fold the card early")
    func warmupsDoNotConsumeThePlan() {
        let card = PlanFixture.card(
            sets: [PlanFixture.warmupSet(order: 0), PlanFixture.workingSet(order: 1)],
            planned: [PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 2)]
        )
        #expect(!card.isComplete)
    }

    @Test("The lifter's check-off folds a card the plan would have kept open")
    func theCheckOffOutranksThePlan() {
        // `FR-15.3.4`'s control is what the self-fold leaves standing: three of five sets can be
        // enough for the day, and the plan having more to say is exactly when a lifter reaches for
        // it.
        let card = PlanFixture.card(
            sets: [PlanFixture.workingSet(order: 0)],
            planned: [PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 3)],
            isMarkedDone: true
        )
        #expect(!card.isComplete)
        #expect(card.isDone)
    }
}
