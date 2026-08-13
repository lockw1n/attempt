import Foundation
import SeedContent
import Testing

@testable import SeedImport

// The ordering exists because `SeedCatalogue.exercises` is in authoring order and `save` refuses a
// `parentExerciseID` naming a row that does not exist yet. Tested here on its own as well as through
// the importer: the end-to-end test says a catalogue imports, and these say why.

@Suite("Ordering a catalogue parent-first")
struct SeedExerciseOrderingTests {
    @Test("A variation authored above its parent is moved below it")
    func aVariationIsMovedBelowItsParent() throws {
        let entries = try decoded(
            payload([
                child(frontSquatID, "Front Squat", of: squatID),
                AuthoredEntry(squatID, "Back Squat"),
            ]))

        let ordered = SeedExerciseOrdering.parentsFirst(entries)

        #expect(ordered.map(\.id) == [squatID, frontSquatID])
    }

    @Test("A chain three deep is ordered whatever order it was authored in")
    func aChainThreeDeepIsOrdered() throws {
        let entries = try decoded(
            payload([
                child(paceSquatID, "Paused Front Squat", of: frontSquatID),
                child(frontSquatID, "Front Squat", of: squatID),
                AuthoredEntry(squatID, "Back Squat"),
            ]))

        let ordered = SeedExerciseOrdering.parentsFirst(entries)

        #expect(ordered.map(\.id) == [squatID, frontSquatID, paceSquatID])
    }

    @Test("Entries that need no moving keep their authoring positions")
    func orderingIsStable() throws {
        let entries = try decoded(
            payload([
                AuthoredEntry(benchID, "Bench Press"),
                AuthoredEntry(squatID, "Back Squat"),
                child(frontSquatID, "Front Squat", of: squatID),
            ]))

        let ordered = SeedExerciseOrdering.parentsFirst(entries)

        #expect(ordered.map(\.id) == [benchID, squatID, frontSquatID])
    }

    @Test("An entry naming a parent the payload does not contain is not held back")
    func aDanglingParentDoesNotHoldAnEntryBack() throws {
        // The validator refuses this payload, but the ordering has to be total on it anyway: the
        // parent may be a row the store already carries, and if it is not, `save` names the fault.
        let entries = try decoded(
            payload([
                child(frontSquatID, "Front Squat", of: absentID),
                AuthoredEntry(squatID, "Back Squat"),
            ]))

        let ordered = SeedExerciseOrdering.parentsFirst(entries)

        #expect(ordered.map(\.id) == [frontSquatID, squatID])
    }

    @Test("A parent chain that closes on itself is emitted rather than looped over")
    func aCycleTerminates() throws {
        let entries = try decoded(
            payload([
                AuthoredEntry(benchID, "Bench Press"),
                child(squatID, "Back Squat", of: frontSquatID),
                child(frontSquatID, "Front Squat", of: squatID),
            ]))

        let ordered = SeedExerciseOrdering.parentsFirst(entries)

        #expect(ordered.map(\.id) == [benchID, squatID, frontSquatID])
    }

    @Test("An entry that is its own parent is emitted rather than looped over")
    func aSelfParentTerminates() throws {
        let entries = try decoded(payload([child(squatID, "Back Squat", of: squatID)]))

        let ordered = SeedExerciseOrdering.parentsFirst(entries)

        #expect(ordered.map(\.id) == [squatID])
    }

    @Test("An empty catalogue orders to an empty catalogue")
    func anEmptyCatalogueIsOrdered() throws {
        #expect(SeedExerciseOrdering.parentsFirst(try decoded(payload([]))).isEmpty)
    }
}

/// A variation of `parent`.
func child(_ id: UUID, _ name: String, of parent: UUID) -> AuthoredEntry {
    var entry = AuthoredEntry(id, name)
    entry.parentExerciseID = parent
    return entry
}
