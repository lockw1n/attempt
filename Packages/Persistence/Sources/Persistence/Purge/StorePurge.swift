import Foundation
import SwiftData

/// The one routine allowed to hard-delete (`G-1.3`, `TR-1.14`).
///
/// **Nothing the lifter can tap reaches it, and that is this task's decision rather than an
/// omission.** `FR-1.10`'s five settings sub-items name no trash and no deletion of any kind, and
/// `FR-1.11.4`'s restore reads a file into the store rather than removing rows from it — so a
/// user-facing control here would be a screen with no requirement behind it. What does have a
/// requirement is `DOD-1.3`'s "export → wipe → restore", whose wipe is ``PurgeScope/everything``.
///
/// **There is no automatic age-based purge either**, for two reasons that outlive the first. Sync is
/// off (`OUT-0.2`) and turning it on is `TR-1.9`'s work: a hard delete mirrors, so a device
/// reclaiming rows on a timer would, at the moment sync is switched on, propagate deletions of rows
/// another device still holds — and there is no second timestamp that could tell that apart from a
/// deliberate delete. And a restore reinstates a soft-deleted row as live, so a purge running on its
/// own schedule would silently change what a round trip yields, which is the criterion `DOD-1.3`
/// measures.
///
/// **The consequence is worth stating plainly: on a lifter's device in this phase, soft-deleted rows
/// are never reclaimed.** The routine is correct and tested and has no shipping caller. That is the
/// safe direction — `G-1.3`'s dangerous half was always the hard delete — but it is a gap, not a
/// finished story, and the phase that switches sync on is where it needs an owner.
@ModelActor
actor StorePurge {
    /// Removes every row the scope frees, and reports what the policy held back.
    ///
    /// - Parameter scope: Which rows are eligible.
    /// - Returns: How many rows went and how many eligible ones stayed.
    /// - Throws: Whatever a fetch or the save throws.
    func purge(_ scope: PurgeScope) throws -> PurgeReport {
        let plan = try PurgePlan(context: modelContext, scope: scope)
        let doomed = plan.doomedRows
        for row in doomed { modelContext.delete(row) }
        try modelContext.saveStamped()
        return PurgeReport(removed: doomed.count, retained: plan.retainedCount)
    }
}

extension PersistenceStack {
    /// Hard-deletes what `scope` frees — the only path in the app that hard-deletes anything
    /// (`G-1.3`).
    ///
    /// The policy, and why a call can legitimately remove less than the scope names, is in
    /// `PurgePolicy.swift`; who may call this at all is on ``StorePurge``.
    ///
    /// - Parameter scope: Which rows are eligible.
    /// - Returns: How many rows went and how many eligible ones stayed.
    /// - Throws: Whatever a fetch or the save throws.
    @discardableResult
    public func purge(_ scope: PurgeScope) async throws -> PurgeReport {
        try await purgeRoutine.purge(scope)
    }
}
