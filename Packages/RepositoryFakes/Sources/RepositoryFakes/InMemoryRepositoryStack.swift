import Foundation
import RepositoryInterface

/// The five fakes over one store — the shape `PersistenceStack` has, without a store file.
///
/// **The five share a store, because the contract is cross-table.** Saving an entry checks that its
/// session and its exercise exist, and those live in tables another repository owns; five
/// independent fakes could not refuse a dangling reference at all, which is the largest thing a
/// caller's test would then be passing against a fiction about.
///
/// For previews and for a caller's unit tests. The conformance suite in this package's tests is
/// what says it behaves like the real one.
public struct InMemoryRepositoryStack: Sendable {
    /// The exercise catalogue and each exercise's training-max history.
    public let exercises: any ExerciseRepository

    /// Sessions, entries and sets.
    public let workouts: any WorkoutRepository

    /// The single settings row (`TR-1.10`).
    public let settings: any SettingsRepository

    /// The bodyweight log.
    public let bodyweight: any BodyweightRepository

    /// The user's equipment profiles.
    public let equipment: any EquipmentRepository

    /// Five fakes over one empty store.
    public init() {
        let store = InMemoryRepositoryStore()
        exercises = InMemoryExerciseRepository(store: store)
        workouts = InMemoryWorkoutRepository(store: store)
        settings = InMemorySettingsRepository(store: store)
        bodyweight = InMemoryBodyweightRepository(store: store)
        equipment = InMemoryEquipmentRepository(store: store)
    }
}
