import Foundation
import PowerliftingCore
import SeedContent

/// Puts a catalogue into an order a repository will accept.
enum SeedExerciseOrdering {
    /// `exercises` reordered so that an entry whose parent the payload also contains comes after it.
    ///
    /// The rule, and what it deliberately does not do about a parent the payload omits or a cycle,
    /// is ``PowerliftingCore/ParentOrdering/parentsFirst(_:id:parentID:)``'s — a restore writes the
    /// same self-referencing table from a backup file and needs the same answer.
    ///
    /// - Parameter exercises: The payload, in authoring order.
    /// - Returns: The same entries, parents first.
    static func parentsFirst(_ exercises: [SeedExercise]) -> [SeedExercise] {
        ParentOrdering.parentsFirst(exercises, id: \.id, parentID: \.parentExerciseID)
    }
}
