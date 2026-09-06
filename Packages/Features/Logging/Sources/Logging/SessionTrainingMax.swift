import Foundation
import PowerliftingCore
import RepositoryInterface

/// The training max a session's loads are read against (`FR-16.7.1`).
///
/// **One home for "the session's day, not today's".** Two stores build the same join — the workout
/// in progress and a finished one — and a rule stated twice is a rule one of them can be corrected
/// out of. A training max raised after a workout must not rewrite what that workout's sets were a
/// percentage of, and this is the single call that guarantees it.
///
/// Not derived, and nothing here computes: `OUT-16.2`. What the lookup answers is which entered
/// number was in force, and `nil` where none ever was.
enum SessionTrainingMax {
    /// The number in force for one exercise on a session's training day, or `nil`.
    ///
    /// - Parameters:
    ///   - repository: Where the history lives.
    ///   - exerciseID: The exercise performed.
    ///   - day: The session's training day.
    /// - Returns: The weight, or `nil` where the exercise has never had one.
    /// - Throws: Whatever the repository throws reading the history.
    static func inForce(
        _ repository: any TrainingMaxRepository,
        forExerciseID exerciseID: UUID,
        on day: Date
    ) async throws -> Weight? {
        try await repository.trainingMax(forExerciseID: exerciseID, on: day)?.newWeight
    }
}
