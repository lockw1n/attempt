import DerivedValues
import Logging
import RepositoryFakes
import RepositoryInterface

/// Building an ``ActiveSessionStore`` in a test, without naming the two repositories most of them
/// do not care about.
///
/// The store is assembled from four protocols and nearly every test here exercises exactly one of
/// them — the workouts. Naming the other three at each of thirty call sites is thirty chances for a
/// test to be reading a catalogue or a settings row some other test wrote.
extension ActiveSessionStore {
    /// A store over `repository`, with a catalogue and a settings row nothing else can see.
    ///
    /// The settings row is the fakes' own default, so ``ActiveSessionStore/displayUnit`` resolves to
    /// kilograms — which is also what it holds before anything has read one. The planned targets
    /// come from that private stack too, so a store built this way has no plan on any card: a
    /// routine-started workout needs ``over(_:)`` and one stack.
    ///
    /// - Parameter repository: The workout repository under test.
    /// - Returns: The store.
    static func overWorkouts(
        _ repository: any WorkoutRepository & PlannedTargetRepository
    ) -> ActiveSessionStore {
        let fakes = InMemoryRepositoryStack()
        return ActiveSessionStore(
            repository: repository,
            catalogue: fakes.exercises,
            settings: fakes.settings,
            records: PersonalRecordRecomputer(
                workouts: repository,
                cache: fakes.personalRecords),
            trainingMaxes: fakes.trainingMaxes)
    }

    /// A store over a whole fake stack, recompute actor included.
    ///
    /// The form for a test that has already seeded a catalogue and a session into one stack, where
    /// ``overWorkouts(_:)``'s private catalogue would be the wrong one.
    ///
    /// - Parameter stack: The fakes the workout is assembled from.
    /// - Returns: The store.
    static func over(_ stack: InMemoryRepositoryStack) -> ActiveSessionStore {
        ActiveSessionStore(
            repository: stack.workouts,
            catalogue: stack.exercises,
            settings: stack.settings,
            records: PersonalRecordRecomputer(
                workouts: stack.workouts,
                cache: stack.personalRecords),
            trainingMaxes: stack.trainingMaxes)
    }
}
