import ExerciseLibrary
import RepositoryFakes
import RepositoryInterface

/// Building an ``ExerciseListState`` in a test, without naming the repository most of them do not
/// care about.
///
/// The list state reads two: the catalogue, which is what every test here is about, and what has
/// been logged, which only `FR-1.1.2`'s recency filter touches. The recency tests build the state
/// directly and hand it a repository they have written into; everything else goes through here and
/// gets one nothing has trained against.
extension ExerciseListState {
    /// A list state over `repository`, with nothing logged behind it.
    ///
    /// - Parameter repository: The catalogue under test.
    /// - Returns: The state.
    static func overCatalogue(_ repository: any ExerciseRepository) -> ExerciseListState {
        ExerciseListState(repository: repository, workouts: InMemoryRepositoryStack().workouts)
    }
}
