import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

@Suite("SetEntryEntity")
struct SetEntryEntityTests {
    // G-1.8. That `init` refuses to compile without both flags is the enforcement, and no test can
    // observe it; what is mechanical is that both values survive the store in both directions, so a
    // warmup and a working set stay distinguishable. Each side is anchored to a literal — comparing
    // one row's flag with another's would pass just as well if the column always read `false`.
    @Test("Both classification flags survive a save and a re-read, in both directions")
    func classificationFlagsRoundTrip() throws {
        let context = try makeTrainingContext()
        let entry = UUID()
        let warmup = makeSet(entryID: entry, order: 0, isWarmup: true, isCompleted: true)
        let planned = makeSet(entryID: entry, order: 1, isWarmup: false, isCompleted: false)
        context.insert(warmup)
        context.insert(planned)
        try context.saveStamped()

        let stored = try context.fetch(
            FetchDescriptor<SetEntryEntity>.notDeleted(sortBy: [SortDescriptor(\.order)])
        )

        #expect(stored.map(\.order) == [0, 1])
        #expect(stored.map(\.isWarmup) == [true, false])
        #expect(stored.map(\.isCompleted) == [true, false])
    }

    // TR-0.2.3's canonical order is a storage contract, not a convenience: it is what makes
    // belt+sleeves the same set of modifiers as sleeves+belt, and what keeps the stored form stable.
    @Test("Modifiers are deduplicated and sorted by raw spelling")
    func modifiersAreCanonicalised() {
        let set = makeSet(
            entryID: UUID(),
            order: 0,
            isWarmup: false,
            isCompleted: true,
            modifiers: [SetModifier(.sleeves), SetModifier(.belt), SetModifier(.sleeves)]
        )

        #expect(set.modifiers == ["belt", "sleeves"])
    }

    // The opposite answer to the vocabulary columns on ExerciseEntity, and deliberately so: nothing
    // re-supplies a modifier the user logged, so degrading one to a known spelling destroys the only
    // copy there is.
    @Test("A modifier no term answers to is kept verbatim")
    func unknownModifierIsPreserved() throws {
        let context = try makeTrainingContext()
        let set = makeSet(
            entryID: UUID(),
            order: 0,
            isWarmup: false,
            isCompleted: true,
            modifiers: [SetModifier(rawValue: "chains"), SetModifier(.belt)]
        )
        context.insert(set)
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<SetEntryEntity>.notDeleted()).first
        )

        #expect(stored.modifiers == ["belt", "chains"])
        #expect(SetModifier(rawValue: "chains").isKnown == false)
    }

    @Test("No modifiers is an empty list, not a missing one")
    func noModifiersIsEmpty() {
        let set = makeSet(entryID: UUID(), order: 0, isWarmup: false, isCompleted: true)

        #expect(set.modifiers == [])
    }

    // `modifiers` is private(set), so this is the only way to rewrite the list — which is the point:
    // the canonical order is a storage contract and a plain `var` would let a caller break it in
    // silence. Round-tripped as well, because `private(set)` on a @Model property is not obviously
    // something SwiftData can still materialise through.
    @Test("replaceModifiers canonicalises, and the result survives the store")
    func replaceModifiersCanonicalises() throws {
        let context = try makeTrainingContext()
        let set = makeSet(
            entryID: UUID(),
            order: 0,
            isWarmup: false,
            isCompleted: true,
            modifiers: [SetModifier(.belt)]
        )
        context.insert(set)
        try context.saveStamped()

        set.replaceModifiers(with: ["wraps", "chains", "wraps", "belt"])
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<SetEntryEntity>.notDeleted()).first
        )

        #expect(stored.modifiers == ["belt", "chains", "wraps"])
    }

    // TR-0.2.3: a band- or machine-assisted set is a negative *added* load, so the column is signed
    // and nothing rewrites the number on its way in (G-1.6).
    @Test("A negative load is stored unmodified")
    func assistedWorkStoresANegativeLoad() throws {
        let context = try makeTrainingContext()
        let set = makeSet(
            entryID: UUID(),
            order: 0,
            isWarmup: false,
            isCompleted: true,
            weightGrams: -20_000,
            reps: 8
        )
        context.insert(set)
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<SetEntryEntity>.notDeleted()).first
        )

        #expect(stored.weightGrams == -20_000)
    }

    // G-1.6 forbids the app rewriting one effort field to agree with the other, so both are stored
    // as entered even when they contradict — RPE 8 implies 2 reps in reserve, not 5.
    @Test("RPE and RIR are independent, and either may be absent")
    func effortFieldsAreIndependent() throws {
        let context = try makeTrainingContext()
        let entry = UUID()
        let contradictory = makeSet(
            entryID: entry,
            order: 0,
            isWarmup: false,
            isCompleted: true,
            rpe: 8,
            rir: 5
        )
        let neither = makeSet(entryID: entry, order: 1, isWarmup: false, isCompleted: true)
        context.insert(contradictory)
        context.insert(neither)
        try context.saveStamped()

        let stored = try context.fetch(
            FetchDescriptor<SetEntryEntity>.notDeleted(sortBy: [SortDescriptor(\.order)])
        )

        #expect(stored.map(\.order) == [0, 1])
        #expect(stored.map(\.rpe) == [8, nil])
        #expect(stored.map(\.rir) == [5, nil])
    }

    // A prescribed set that was never performed carries its targets and isCompleted == false — the
    // combination the schema has to be able to hold for TR-0.3.4's target columns to mean anything.
    // The performed set beside it is what stops the nil assertions passing vacuously: completedAt
    // has to be readable back before "the unperformed one has none" says anything at all.
    @Test("A prescribed set keeps its targets; a performed one keeps what it did")
    func prescribedAndPerformedSetsDiffer() throws {
        let context = try makeTrainingContext()
        let finished = Date(timeIntervalSince1970: 1_700_000_000)
        let performed = makeSet(
            entryID: UUID(),
            order: 0,
            isWarmup: false,
            isCompleted: true,
            weightGrams: 150_000,
            targetWeightGrams: 152_500,
            targetReps: 5,
            completedAt: finished
        )
        let prescribed = makeSet(
            entryID: UUID(),
            order: 1,
            isWarmup: false,
            isCompleted: false,
            weightGrams: 0,
            reps: 0,
            targetWeightGrams: 152_500,
            targetReps: 5
        )
        context.insert(performed)
        context.insert(prescribed)
        try context.saveStamped()

        let stored = try context.fetch(
            FetchDescriptor<SetEntryEntity>.notDeleted(sortBy: [SortDescriptor(\.order)])
        )

        #expect(stored.map(\.order) == [0, 1])
        #expect(stored.map(\.targetWeightGrams) == [152_500, 152_500])
        #expect(stored.map(\.targetReps) == [5, 5])
        #expect(stored.map(\.weightGrams) == [150_000, 0])
        #expect(stored.map(\.reps) == [5, 0])
        #expect(stored.map(\.isCompleted) == [true, false])
        #expect(stored.map(\.completedAt) == [finished, nil])
    }
}
