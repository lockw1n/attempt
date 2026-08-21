import Logging
import RepositoryFakes
import RepositoryInterface

/// Building an ``ActiveSessionStore`` in a test, without naming the two repositories most of them
/// do not care about.
///
/// The store is assembled from three protocols and nearly every test here exercises exactly one of
/// them — the workouts. Naming the other two at each of thirty call sites is thirty chances for a
/// test to be reading a catalogue or a settings row some other test wrote.
extension ActiveSessionStore {
    /// A store over `repository`, with a catalogue and a settings row nothing else can see.
    ///
    /// The settings row is the fakes' own default, so ``ActiveSessionStore/displayUnit`` resolves to
    /// kilograms — which is also what it holds before anything has read one.
    ///
    /// - Parameter repository: The workout repository under test.
    /// - Returns: The store.
    static func overWorkouts(_ repository: any WorkoutRepository) -> ActiveSessionStore {
        let fakes = InMemoryRepositoryStack()
        return ActiveSessionStore(
            repository: repository, catalogue: fakes.exercises, settings: fakes.settings)
    }
}
