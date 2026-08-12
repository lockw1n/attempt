import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@Suite("Records")
struct RecordTests {
    // The only behaviour StoredRecord has. Both sides are anchored to a literal rather than to
    // `record.deletedAt != nil`, which would compare the definition with itself.
    @Test("A record is soft-deleted exactly when it carries a deletion date")
    func softDeletionReadsTheDate() {
        #expect(makeExercise(deletedAt: nil).isSoftDeleted == false)
        #expect(makeExercise(deletedAt: fixtureUpdatedAt).isSoftDeleted == true)
    }

    // Equality is synthesised today, so this cannot fail today — it is here for T-0.41, which adds
    // Codable and may hand-write a conformance beside it. A record that compared equal while
    // differing in `isWarmup` or `isCompleted` would make G-1.8's two flags untestable through
    // every fake and every round-trip built on it, which is the failure worth a regression test
    // rather than the field count.
    @Test(
        "A set record differing in one field is a different record",
        arguments: [
            makeSetEntry(order: 4),
            makeSetEntry(reps: 6),
            makeSetEntry(rpe: nil),
            makeSetEntry(rir: nil),
            makeSetEntry(isWarmup: false),
            makeSetEntry(isCompleted: false),
            makeSetEntry(notes: ""),
            makeSetEntry(modifiers: []),
        ]
    )
    func setRecordsCompareOnEveryField(_ mutated: SetEntry) {
        let baseline = makeSetEntry(id: mutated.id)
        #expect(mutated != baseline)
    }

    // An unrecognised modifier spelling has no other copy — nothing re-supplies one the user
    // configured — so the record carries `SetModifier`, which keeps the raw string, rather than a
    // closed term enum that would drop it. The fixture's second spelling is deliberately not a
    // `SetModifierTerm`.
    @Test("An unrecognised modifier survives on the record")
    func unknownModifierIsPreserved() {
        let modifiers = makeSetEntry().modifiers

        #expect(modifiers.map(\.rawValue).contains("curriculum"))
        #expect(modifiers.contains { $0.known == nil })
    }

    // The stored column is canonical and `replaceModifiers(with:)` is its only writer, so a record
    // that kept what it was handed would compare unequal to the same set read back — and a fake
    // storing the caller's array would disagree with the real store on read-back, which is exactly
    // what a shared conformance suite is meant to catch rather than inherit.
    //
    // Anchored to a literal on one side: asserting `a.modifiers == b.modifiers` over two records
    // built from differently-ordered inputs passes for a record that canonicalises *and* for one
    // that sorts nothing but was handed the same array twice.
    //
    // Five denominations rather than two, and that is about the probe rather than the code. The
    // mutation worth catching here is `Array(Set(modifiers))` — deduplicated, unsorted — whose own
    // output order is nondeterministic, so it cannot be scored from a single run: with two elements
    // it passes about half the time. At five it is 1 in 120, which is the difference between a
    // probe that measures something and a coin.
    @Test("A record canonicalises its modifiers rather than trusting the caller")
    func modifiersAreCanonicalised() {
        let entry = makeSetEntry(
            modifiers: [
                SetModifier(rawValue: "sleeves"), SetModifier(rawValue: "belt"),
                SetModifier(rawValue: "wraps"), SetModifier(rawValue: "sleeves"),
                SetModifier(rawValue: "deficit"), SetModifier(rawValue: "paused"),
            ]
        )

        #expect(
            entry.modifiers.map(\.rawValue) == ["belt", "deficit", "paused", "sleeves", "wraps"]
        )
    }

    // The consequence the canonical form exists for, and it is the one a caller would hit: two
    // records describing the same set are the same record whichever order the modifiers arrived in.
    @Test("Modifier order and repetition do not change the record")
    func modifierOrderDoesNotChangeIdentity() {
        let id = UUID()
        let one = makeSetEntry(
            id: id,
            modifiers: [SetModifier(rawValue: "belt"), SetModifier(rawValue: "sleeves")]
        )
        let other = makeSetEntry(
            id: id,
            modifiers: [
                SetModifier(rawValue: "sleeves"), SetModifier(rawValue: "belt"),
                SetModifier(rawValue: "belt"),
            ]
        )

        #expect(one == other)
    }
}
