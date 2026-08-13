import Foundation
import SeedContent

/// Puts a catalogue into an order a repository will accept.
enum SeedExerciseOrdering {
    /// `exercises` reordered so that an entry whose parent the payload also contains comes after it.
    ///
    /// **Stable within that constraint**: entries the ordering does not have to move keep their
    /// authoring positions, so a diff of what an import writes stays readable against the file.
    ///
    /// Total on every input, including two the validator refuses. An entry naming a parent the
    /// payload does not contain is not held back — the row it needs may already be stored, and if it
    /// is not, `save` names the fault. A parent chain that closes on itself cannot be ordered at
    /// all, so its members are emitted in authoring order rather than looped over.
    static func parentsFirst(_ exercises: [SeedExercise]) -> [SeedExercise] {
        let present = Set(exercises.map(\.id))
        var emitted: Set<UUID> = []
        var ordered: [SeedExercise] = []
        ordered.reserveCapacity(exercises.count)
        var pending = exercises

        while !pending.isEmpty {
            var deferred: [SeedExercise] = []
            for entry in pending {
                // Blocked only by a parent this payload carries: one it does not is either already
                // stored or a fault `save` will name, and holding the entry back answers neither.
                let waiting = entry.parentExerciseID.map {
                    present.contains($0) && !emitted.contains($0)
                }
                if waiting == true {
                    deferred.append(entry)
                } else {
                    ordered.append(entry)
                    emitted.insert(entry.id)
                }
            }
            guard deferred.count < pending.count else {
                ordered.append(contentsOf: deferred)
                break
            }
            pending = deferred
        }
        return ordered
    }
}
