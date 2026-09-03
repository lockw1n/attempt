import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-1.2.14`'s two independent sequences.
///
/// **These are the requirement's own claims, not the view's.** The rule is a function over a list,
/// so every case here is an assertion about numbers rather than about pixels — which is what lets
/// the interesting ones (an insertion between two working sets; a set reclassified after the fact)
/// be written at all, neither having a control behind it that a rendering test could drive.
@Suite("Set numbering")
struct SetNumberingTests {
    @Test("Warmups and working sets carry two independent sequences")
    func twoSequences() {
        let sets = [
            SetEntry.numbering(isWarmup: true, reps: 5),
            SetEntry.numbering(isWarmup: true, reps: 5),
            SetEntry.numbering(isWarmup: false, reps: 3),
            SetEntry.numbering(isWarmup: false, reps: 3),
            SetEntry.numbering(isWarmup: false, reps: 3),
        ]

        let numbered = SetNumbering.numbered(sets)

        // The task's own example: two warmups then three working sets is W1, W2 and 1, 2, 3.
        #expect(numbered.filter(\.isWarmup).map(\.number) == [1, 2])
        #expect(numbered.filter { !$0.isWarmup }.map(\.number) == [1, 2, 3])
    }

    @Test("A working set inserted between working sets 1 and 2 renumbers the work and nothing else")
    func insertionBetweenWorkingSets() {
        var sets = [
            SetEntry.numbering(isWarmup: true, reps: 5),
            SetEntry.numbering(isWarmup: true, reps: 5),
            SetEntry.numbering(isWarmup: false, reps: 3),
            SetEntry.numbering(isWarmup: false, reps: 3),
            SetEntry.numbering(isWarmup: false, reps: 3),
        ]
        let inserted = SetEntry.numbering(isWarmup: false, reps: 1)

        // Between working sets 1 and 2, which is index 3 — the two warmups are ahead of it.
        sets.insert(inserted, at: 3)
        let numbered = SetNumbering.numbered(sets)

        // Four working sets, numbered through, with the newcomer second.
        #expect(numbered.filter { !$0.isWarmup }.map(\.number) == [1, 2, 3, 4])
        #expect(numbered.first { $0.id == inserted.id }?.number == 2)
        // And the warmups are untouched — the half of FR-1.2.14 that a shared counter would break.
        #expect(numbered.filter(\.isWarmup).map(\.number) == [1, 2])
    }

    @Test("Marking a working set as a warmup renumbers both sequences")
    func reclassifyingRenumbersBoth() {
        let third = SetEntry.numbering(isWarmup: false, reps: 3)
        let sets = [
            SetEntry.numbering(isWarmup: true, reps: 5),
            SetEntry.numbering(isWarmup: false, reps: 3),
            SetEntry.numbering(isWarmup: false, reps: 3),
            third,
        ]
        #expect(SetNumbering.numbered(sets).filter(\.isWarmup).map(\.number) == [1])
        #expect(SetNumbering.numbered(sets).filter { !$0.isWarmup }.map(\.number) == [1, 2, 3])

        let marked = sets.map { $0.id == third.id ? $0.asWarmup() : $0 }
        let numbered = SetNumbering.numbered(marked)

        // One leaves the work and joins the warmups, and both sequences close up behind it.
        #expect(numbered.filter(\.isWarmup).map(\.number) == [1, 2])
        #expect(numbered.filter { !$0.isWarmup }.map(\.number) == [1, 2])
        #expect(numbered.first { $0.id == third.id }?.number == 2)
    }

    @Test("A warmup between two working sets does not advance the working count")
    func interleavedWarmupIsSkipped() {
        // The order the card renders is grouped, but the rule is applied to the stored order — so
        // this is the case that proves the two counters are independent rather than that the view
        // happens to partition first.
        let sets = [
            SetEntry.numbering(isWarmup: false, reps: 3),
            SetEntry.numbering(isWarmup: true, reps: 5),
            SetEntry.numbering(isWarmup: false, reps: 3),
        ]

        #expect(SetNumbering.numbered(sets).map(\.number) == [1, 1, 2])
    }

    @Test("Numbering is one-based, and the stored order is not the number")
    func numbersAreNotOrders() {
        // `order` is zero-based and carries the gaps a soft delete leaves, which is exactly what a
        // card numbered from it would show. The two must not agree.
        let sets = [
            SetEntry.numbering(isWarmup: false, reps: 5, order: 0),
            SetEntry.numbering(isWarmup: false, reps: 5, order: 2),
            SetEntry.numbering(isWarmup: false, reps: 5, order: 3),
        ]

        let numbered = SetNumbering.numbered(sets)

        #expect(numbered.map(\.number) == [1, 2, 3])
        #expect(numbered.map(\.record.order) == [0, 2, 3])
    }

    @Test("An exercise of nothing but warmups numbers them and produces no working sets")
    func warmupsOnly() {
        let sets = [
            SetEntry.numbering(isWarmup: true, reps: 5),
            SetEntry.numbering(isWarmup: true, reps: 5),
        ]

        let numbered = SetNumbering.numbered(sets)

        #expect(numbered.map(\.number) == [1, 2])
        #expect(numbered.filter { !$0.isWarmup }.isEmpty)
        // Anchored to a literal rather than to another empty collection: `[] == []` holds however
        // the numbering is broken.
        #expect(numbered.count == 2)
    }

    @Test("No sets is no numbers")
    func empty() {
        #expect(SetNumbering.numbered([]).isEmpty)
    }

    @Test("The order handed in is the order handed back")
    func orderIsPreserved() {
        // The card partitions the result, so nothing here may reorder: a caller rendering the list
        // flat and one rendering it grouped have to get the same numbers.
        let sets = [
            SetEntry.numbering(isWarmup: false, reps: 1),
            SetEntry.numbering(isWarmup: true, reps: 2),
            SetEntry.numbering(isWarmup: false, reps: 3),
        ]

        #expect(SetNumbering.numbered(sets).map(\.record.reps) == [1, 2, 3])
    }

    // MARK: - What the card folds on (FR-1.2.14)

    @Test("The warmup group opens while the work has not started, and folds once it has")
    func defaultFold() {
        let warmupsOnly = SessionExercise.numbering(sets: [.numbering(isWarmup: true, reps: 5)])
        let started = SessionExercise.numbering(
            sets: [.numbering(isWarmup: true, reps: 5), .numbering(isWarmup: false, reps: 3)])

        #expect(warmupsOnly.hasWorkingSets == false)
        #expect(started.hasWorkingSets == true)
        #expect(SessionExerciseList.defaultWarmupExpansion(for: warmupsOnly) == true)
        #expect(SessionExerciseList.defaultWarmupExpansion(for: started) == false)
    }

    @Test("An exercise of warmups alone is not complete — it has not started")
    func warmupsDoNotCompleteAnExercise() {
        // The same partition `hasWorkingSets` makes, one step later: three completed warmups are
        // not a finished exercise, and a card that collapsed on them would hide an exercise the
        // user has not done yet.
        let warmupsOnly = SessionExercise.numbering(
            sets: [.numbering(isWarmup: true, reps: 5), .numbering(isWarmup: true, reps: 5)])

        #expect(warmupsOnly.isComplete == false)
    }
}

/// `FR-16.1.1`'s groups carrying `FR-1.2.14`'s numbers.
@Suite("Numbered set groups")
struct NumberedSetGroupTests {
    @Test("A group is numbered by its first set and its last")
    func aGroupSpansARange() {
        let sets = (0..<4).map { _ in SetEntry.numbering(isWarmup: false, reps: 6) }
        let groups = SetNumbering.grouped(SetNumbering.numbered(sets))

        #expect(groups.count == 1)
        #expect(groups[0].numbers == 1...4)
        #expect(groups[0].count == 4)
        #expect(!groups[0].isSingle)
    }

    @Test("A group of one spans one number")
    func aLoneSetIsItsOwnRange() {
        let groups = SetNumbering.grouped(
            SetNumbering.numbered([SetEntry.numbering(isWarmup: false, reps: 6)]))

        #expect(groups[0].numbers == 1...1)
        #expect(groups[0].isSingle)
    }

    @Test("Every number survives the grouping, in order")
    func theNumbersAreNeitherLostNorReordered() {
        // Grouping is a partition of the numbered list, so the members read back as `1, 2, 3, 4, 5`
        // however the runs fall — which is what makes the badge a range rather than a fifth number.
        let sets = [
            SetEntry.numbering(isWarmup: false, reps: 6),
            SetEntry.numbering(isWarmup: false, reps: 6),
            SetEntry.numbering(isWarmup: false, reps: 3),
            SetEntry.numbering(isWarmup: false, reps: 6),
            SetEntry.numbering(isWarmup: false, reps: 6),
        ]

        let groups = SetNumbering.grouped(SetNumbering.numbered(sets))

        #expect(groups.map(\.count) == [2, 1, 2])
        #expect(groups.flatMap { $0.members.map(\.number) } == [1, 2, 3, 4, 5])
        #expect(groups.map(\.numbers) == [1...2, 3...3, 4...5])
    }

    @Test("A warmup group is numbered in the warmups' own sequence")
    func warmupsKeepTheirOwnRange() {
        // The card partitions before it groups, so a warmup group's range is `W1–2` and the working
        // group beside it still starts at 1.
        let numbered = SetNumbering.numbered([
            SetEntry.numbering(isWarmup: true, reps: 5),
            SetEntry.numbering(isWarmup: true, reps: 5),
            SetEntry.numbering(isWarmup: false, reps: 6),
            SetEntry.numbering(isWarmup: false, reps: 6),
        ])

        let warmups = SetNumbering.grouped(numbered.filter(\.isWarmup))
        let working = SetNumbering.grouped(numbered.filter { !$0.isWarmup })

        #expect(warmups.map(\.numbers) == [1...2])
        #expect(warmups.map(\.isWarmup) == [true])
        #expect(working.map(\.numbers) == [1...2])
    }
}

extension SetEntry {
    /// A set with every field fixed but the three these tests vary.
    ///
    /// - Parameters:
    ///   - isWarmup: Which sequence it belongs to.
    ///   - reps: Something to tell one set from another by, where the id is not convenient.
    ///   - order: The stored position. Zero unless a test is about the gap one leaves.
    /// - Returns: The set.
    fileprivate static func numbering(isWarmup: Bool, reps: Int, order: Int = 0) -> SetEntry {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return SetEntry(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            entryID: UUID(),
            order: order,
            weight: Weight(grams: 100_000),
            reps: reps,
            rpe: nil,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: true,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil
        )
    }

    /// This set as a warmup, and every other field untouched — what `FR-1.2.4`'s marking does.
    fileprivate func asWarmup() -> SetEntry {
        SetEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            entryID: entryID,
            order: order,
            weight: weight,
            reps: reps,
            rpe: rpe,
            rir: rir,
            isWarmup: true,
            isCompleted: isCompleted,
            targetWeight: targetWeight,
            targetReps: targetReps,
            modifiers: modifiers,
            notes: notes,
            completedAt: completedAt
        )
    }
}

extension SessionExercise {
    /// One card's worth of workout, with only its sets varying.
    fileprivate static func numbering(sets: [SetEntry]) -> SessionExercise {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return SessionExercise(
            entry: ExerciseEntry(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: UUID(),
                exerciseID: UUID(),
                order: 0,
                notes: ""
            ),
            exercise: nil,
            sets: sets
        )
    }
}
