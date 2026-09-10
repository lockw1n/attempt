import DerivedValues
import Foundation
import RepositoryInterface

/// Rewriting a whole group of logged sets to what the Log sheet now says (`FR-17.7.5`,
/// `FR-17.1.3`'s rewrite in the sheet's shape).
///
/// **Over ``LoggedSetWriter`` rather than beside it.** A member that survives the rewrite is
/// `FR-1.2.7`'s edit — the same six columns collected, the same nine carried across — so the field
/// mapping is read from that type rather than written again here. What this adds is the two things
/// a single-set edit has no notion of: a lowered count, which soft-deletes the trailing rows
/// (`G-1.3`), and a raised one, which appends.
///
/// **Nothing unchanged is written** (`G-2.4`). Assigning a `@Model` property marks the row changed
/// whatever the value was, so a member that resolves to exactly what is stored is skipped: every
/// save restamps `updatedAt`, the conflict key, and a no-op local write would outrank a real remote
/// edit. Reopening the sheet over an answered row and saving it untouched is the ordinary way to
/// reach that.
///
/// **The group is every set the entry holds, in order — warmups included.** The sheet's per-set
/// fold can mark any member a warmup, so a rewrite that skipped them would leave a row the lifter
/// had just demoted outside the group it belongs to and rewrite the wrong member next time.
///
/// **Every member it writes is work that happened**, which is where it parts company with
/// ``LoggedSetWriter/edited(_:to:)``: that function carries `isCompleted` across because
/// `FR-1.2.5`'s outcome has a control of its own, and this one is the answer to *what did you do*.
/// A member still carrying `isCompleted == false` is a set nobody attempted (`FR-16.4.4`), and
/// left that way a whole group of them would be marked done with no completed working set behind
/// it — which is how a skip is derived (`TR-17.4`), so the sheet's answer would read as *Skipped*.
///
/// **One announcement, at the end, and only where something moved** (`NFR-17.3`, `FR-1.6.4`).
public struct SetGroupRewrite: Sendable {
    /// The sets, and the entries they are read by.
    private let repository: any WorkoutRepository

    /// What is told that the group moved.
    private let records: PersonalRecordRecomputer

    /// Builds the rewrite over the repository the sets live in.
    ///
    /// - Parameters:
    ///   - repository: Sessions, their entries and their sets.
    ///   - records: The app's one recompute actor.
    public init(repository: any WorkoutRepository, records: PersonalRecordRecomputer) {
        self.repository = repository
        self.records = records
    }

    /// Rewrites the entry's sets to `rows`.
    ///
    /// **Position by position, then the tail.** Row *i* rewrites stored set *i*; rows past the end
    /// are appended in order; stored sets past the end of `rows` are soft-deleted. Matching by
    /// position rather than by shape is what lets a lifter turn `80 × 8, 8, 8` into
    /// `80 × 8, 8, 6` without the third row losing its identity — and its `createdAt`,
    /// `completedAt` and outcome with it.
    ///
    /// - Parameters:
    ///   - entryID: The exercise whose group is being rewritten.
    ///   - rows: What it becomes, in order. Empty removes the group.
    /// - Returns: Whether anything was written.
    /// - Throws: Whatever the repository throws reading the entry's sets or writing a row.
    @discardableResult
    public func rewrite(inEntryID entryID: UUID, to rows: [SetEntryValues]) async throws -> Bool {
        let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
            .sorted { $0.order < $1.order }
        var nextOrder = (stored.map(\.order).max() ?? -1) + 1
        var changed = false
        let moment = Date.now
        for (index, values) in rows.enumerated() {
            if index < stored.count {
                let edited = Self.performed(
                    LoggedSetWriter.edited(stored[index], to: values), at: moment)
                guard edited != stored[index] else { continue }
                try await repository.save(edited)
            } else {
                try await repository.save(
                    Self.logged(values, entryID: entryID, order: nextOrder, at: moment))
                nextOrder += 1
            }
            changed = true
        }
        for surplus in stored.dropFirst(rows.count) {
            try await repository.deleteSet(id: surplus.id)
            changed = true
        }
        if changed { await records.setDidChange(inEntryID: entryID) }
        return changed
    }

    /// `set` marked as work that happened.
    ///
    /// **Rebuilt rather than mutated**, on ``LoggedSetWriter/edited(_:to:)``'s reason. A member
    /// already completed comes back equal to itself, which is what the caller's `!=` reads — so
    /// `G-2.4`'s no-op rule is enforced there rather than by a second guard here.
    ///
    /// - Parameters:
    ///   - set: The member, with the form's values already on it.
    ///   - moment: When the group was reported.
    /// - Returns: The record to save.
    static func performed(_ set: SetEntry, at moment: Date) -> SetEntry {
        SetEntry(
            id: set.id,
            createdAt: set.createdAt,
            updatedAt: set.updatedAt,
            deletedAt: set.deletedAt,
            entryID: set.entryID,
            order: set.order,
            weight: set.weight,
            reps: set.reps,
            rpe: set.rpe,
            rir: set.rir,
            isWarmup: set.isWarmup,
            isCompleted: true,
            targetWeight: set.targetWeight,
            targetReps: set.targetReps,
            modifiers: set.modifiers,
            notes: set.notes,
            completedAt: set.completedAt ?? moment
        )
    }

    /// One row as the Log sheet writes it — performed, and completed.
    ///
    /// **`isCompleted` is true and `completedAt` is now**, which is what separates a set the lifter
    /// reported from a planned row nobody has attempted (`FR-16.4.4`). The Log sheet answers *what
    /// did you do*, so every row it writes is work that happened.
    ///
    /// **Neither target column is written.** `FR-15.3.5` keeps the plan out of an answer: what was
    /// prescribed is the routine's, resolved at read time (``SessionExercise/plannedTargets``), and
    /// copying it onto the set would put a second answer in the store.
    ///
    /// - Parameters:
    ///   - values: What the set records.
    ///   - entryID: The exercise it belongs to.
    ///   - order: Its position among that exercise's sets.
    ///   - moment: When it was logged.
    /// - Returns: The record to save.
    static func logged(
        _ values: SetEntryValues, entryID: UUID, order: Int, at moment: Date
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: moment,
            updatedAt: moment,
            deletedAt: nil,
            entryID: entryID,
            order: order,
            weight: values.weight,
            reps: values.reps,
            rpe: values.rpe,
            rir: nil,
            isWarmup: values.isWarmup,
            isCompleted: true,
            targetWeight: nil,
            targetReps: nil,
            modifiers: values.modifiers,
            notes: values.notes,
            completedAt: moment
        )
    }
}
