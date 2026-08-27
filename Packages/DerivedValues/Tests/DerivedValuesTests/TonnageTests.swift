import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-1.5.1`'s tonnage — the first arithmetic Phase 1 does outside `PowerliftingCore`, pinned the
/// way Phase 0 pinned its formulas: against numbers worked out by hand rather than against what the
/// code happens to return.
@Suite("Tonnage")
struct TonnageTests {
    @Test("A hand-computed session: 5×100 + 5×100 + 3×120 is 1,360 kg")
    func handComputed() {
        // 500 + 500 + 360. The third set is a different load and a different rep count, so a
        // transposed multiply — reps × the wrong weight — does not land on the same total.
        let sets = [
            Self.set(kilograms: 100, reps: 5),
            Self.set(kilograms: 100, reps: 5, order: 1),
            Self.set(kilograms: 120, reps: 3, order: 2),
        ]
        #expect(Tonnage.of(sets) == Weight(grams: 1_360_000))
    }

    @Test("Warmups are not in it (G-1.8)")
    func warmupsAreExcluded() {
        let sets = [
            Self.set(kilograms: 60, reps: 5, isWarmup: true),
            Self.set(kilograms: 100, reps: 5, order: 1),
        ]
        // 500, not 800 — and the literal on the right is what stops `nil == nil`'s cousin, a
        // comparison between two things that are both wrong in the same way.
        #expect(Tonnage.of(sets) == Weight(grams: 500_000))
    }

    @Test("A set that was not performed is not in it either (G-1.8)")
    func incompleteSetsAreExcluded() {
        let sets = [
            Self.set(kilograms: 100, reps: 5, isCompleted: false),
            Self.set(kilograms: 100, reps: 2, order: 1),
        ]
        #expect(Tonnage.of(sets) == Weight(grams: 200_000))
    }

    @Test("Assisted work subtracts nothing: a negative load contributes zero, not less than zero")
    func assistedWorkDoesNotReduceTheTotal() {
        // The reason the positive-load clause exists. `SetEntry.weight` is signed on purpose, so
        // summing it verbatim makes a session's tonnage *fall* as more assisted reps are done.
        let assisted = Self.set(kilograms: -20, reps: 8)
        let working = Self.set(kilograms: 100, reps: 5, order: 1)
        #expect(Tonnage.of([assisted]) == .zero)
        #expect(Tonnage.of([assisted, working]) == Tonnage.of([working]))
        #expect(Tonnage.of([working]) == Weight(grams: 500_000))
    }

    @Test("A bodyweight set at zero weighs nothing, and does not fail")
    func bodyweightSetsWeighNothing() {
        #expect(Tonnage.of([Self.set(kilograms: 0, reps: 20)]) == .zero)
    }

    @Test("A negative rep count — what a foreign row looks like — subtracts nothing")
    func negativeRepsAreRefused() {
        // `SetEntry.reps` is unchecked on the way in, so a store this app did not write may carry
        // one. Without the guard it multiplies a positive load into a negative contribution.
        let sets = [Self.set(kilograms: 100, reps: -5), Self.set(kilograms: 100, reps: 5, order: 1)]
        #expect(Tonnage.of(sets) == Weight(grams: 500_000))
    }

    @Test("A rep count that would overflow the total skips its own set, rather than trapping")
    func overflowSkipsTheTerm() {
        // `Weight`'s `*` traps on `Int` overflow and `SetEntry.reps` is unchecked on the way in, so
        // one foreign row would otherwise crash the History tab rather than mis-report a session.
        let absurd = Self.set(kilograms: 100, reps: .max)
        let working = Self.set(kilograms: 100, reps: 5, order: 1)
        #expect(Tonnage.of([absurd]) == .zero)
        #expect(Tonnage.of([absurd, working]) == Weight(grams: 500_000))
        // And the other direction: the running total is already large when the next term arrives.
        let heavy = Self.set(kilograms: Int.max / 2_000, reps: 1)
        #expect(Tonnage.of([heavy, heavy, heavy]) == Tonnage.of([heavy, heavy]))
    }

    @Test("A total carried across entries skips what will not fit, rather than trapping")
    func accumulationDoesNotTrap() {
        // `of(_:)` alone cannot exceed `Int.max`, so the guard inside it says nothing about what
        // two of its answers do when added. A caller summing entries with `+` traps here; through
        // `adding(_:to:)` the term that will not fit is the one that is dropped.
        let heavy = Self.set(kilograms: Int.max / 1_500, reps: 1)
        let running = Tonnage.adding([heavy], to: .zero)
        #expect(running == Weight(grams: (Int.max / 1_500) * 1_000))
        #expect(Tonnage.adding([heavy], to: running) == running)
        // And a term that still fits is still taken, so the guard is not just refusing everything.
        let light = Self.set(kilograms: 100, reps: 5, order: 1)
        #expect(Tonnage.adding([light], to: running) == running + Weight(grams: 500_000))
    }

    @Test("Nothing to weigh is zero, not a refusal")
    func emptyIsZero() {
        #expect(Tonnage.of([SetEntry]()) == .zero)
    }

    @Test("The counted population is completed working sets, whatever they weighed")
    func countedPopulation() {
        // `counts` is deliberately *not* the tonnage population: a set that cannot be weighed was
        // still performed, and the row's set count says so. That difference is the omission the
        // screen does not yet explain (`FR-1.13.3`).
        #expect(Tonnage.counts(Self.set(kilograms: 0, reps: 20)))
        #expect(Tonnage.counts(Self.set(kilograms: -20, reps: 8)))
        #expect(!Tonnage.counts(Self.set(kilograms: 100, reps: 5, isWarmup: true)))
        #expect(!Tonnage.counts(Self.set(kilograms: 100, reps: 5, isCompleted: false)))
    }

    /// One set, with only the four columns the formula reads carrying anything.
    private static func set(
        kilograms: Int,
        reps: Int,
        order: Int = 0,
        isWarmup: Bool = false,
        isCompleted: Bool = true
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            entryID: UUID(),
            order: order,
            weight: Weight(grams: kilograms * 1_000),
            reps: reps,
            rpe: nil,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil
        )
    }
}
