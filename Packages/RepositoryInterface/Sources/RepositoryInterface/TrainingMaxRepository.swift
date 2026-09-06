import Foundation
import PowerliftingCore

/// An exercise's training max: how it is derived, and what it has been (`TR-15.1`, `TR-16.3`,
/// `FR-15.1.1`, `FR-15.1.4`, `FR-16.7.2`).
///
/// **Two tables, and the split is where `G-1.4` lands on this feature.** A ``TrainingMaxEntry`` says
/// how the number is arrived at — the source, and the percentage and rounding rule a derived source
/// would use. A ``TrainingMaxHistoryEntry`` says what the number *was*, from a date, with what it
/// replaced and why. Only the second holds a value, so there is nothing for a "current" column to
/// disagree with: ``trainingMax(forExerciseID:on:)`` is a lookup over the history and never a read
/// of a stored answer.
///
/// **Off ``ExerciseRepository`` rather than on it.** The three configuration methods lived there
/// while a training max was one table hanging off the catalogue; two tables with their own history,
/// their own soft delete and their own archive sections are a boundary of their own, and leaving
/// them on the catalogue would have made "the exercise repository" the name for two unrelated
/// contracts.
public protocol TrainingMaxRepository: Sendable {
    /// The configuration in force for `exerciseID` on `date` — the latest entry effective on or
    /// before it, or `nil` where the user has configured none.
    ///
    /// **No `includingDeleted:`, and it is not an omission** — rule 1's second paragraph in this
    /// module's header. This resolves to the configuration in force, and a soft-deleted entry is one
    /// the user replaced.
    func configuration(forExerciseID exerciseID: UUID, on date: Date) async throws -> TrainingMaxEntry?

    /// Every configuration written for one exercise, newest ``TrainingMaxEntry/effectiveFrom``
    /// first.
    func configurationHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry]

    /// Appends a configuration to the exercise's history (`FR-15.1.1`).
    ///
    /// **Appends.** Saving a configuration that supersedes another does not overwrite it. Re-saving
    /// one that already exists updates that entry, by ``TrainingMaxEntry/id``.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the exercise does
    ///   not exist.
    func saveConfiguration(_ entry: TrainingMaxEntry) async throws

    /// The training max in force for `exerciseID` on `date` — the latest history entry effective on
    /// or before it, or `nil` where the exercise has never had one.
    ///
    /// **`<=`, not `<`.** An entry effective from a day applies *on* that day; the author's plan
    /// file announces a week's number at the week's start, and a strict comparison would leave the
    /// first session of every week reading the previous week's load.
    ///
    /// No `includingDeleted:`, for ``configuration(forExerciseID:on:)``'s reason.
    func trainingMax(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) async throws -> TrainingMaxHistoryEntry?

    /// Every change to one exercise's training max, newest
    /// ``TrainingMaxHistoryEntry/effectiveFrom`` first — the history `FR-15.1.4` displays.
    ///
    /// **Two changes dated the same day list the way ``trainingMax(forExerciseID:on:)`` resolves
    /// them**, so the one in force is the one on top. A correction entered against the day it
    /// corrects would otherwise be listed under the figure it outranks.
    func history(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxHistoryEntry]

    /// Records a change to an exercise's training max (`FR-15.1.4`, `FR-16.7.2`).
    ///
    /// **It writes nothing but this row** (`NFR-15.2`). A training max is what a *future* load is
    /// read against; a set already logged holds the weight that was lifted, and a write here that
    /// touched one would be rewriting the lifter's history to match a number they have only just
    /// entered.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the exercise does
    ///   not exist.
    func save(_ entry: TrainingMaxHistoryEntry) async throws

    /// Soft-deletes one history entry.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live entry carries that id.
    func deleteEntry(id: UUID) async throws
}
