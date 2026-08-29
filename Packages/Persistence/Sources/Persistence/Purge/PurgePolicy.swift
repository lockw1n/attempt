// What a purge removes, and what holds a row back (G-1.3, TR-1.14).
//
// THE WHOLE POLICY IS ONE SENTENCE: A ROW IS REMOVED ONLY WHEN NOTHING THE PURGE LEAVES BEHIND
// STILL NAMES IT. `G-2.5` forbids relationships, so every join in this module is a bare `UUID`
// column that the store does not check — a hard delete on this side of it is the one operation that
// can leave a set pointing at an entry that is not there, and no constraint would notice. The rule
// above is what makes that unreachable, and it needs no separate cascade clause: a session's entry
// names the session, so an entry that survives keeps its session, and a session with no surviving
// entry is free. Ownership and reference are the same edge read in opposite directions.
//
// THE RULE'S SECOND HALF IS THAT A CUTOFF PURGE HARD-DELETES NO LIVE ROW BUT A CACHED ONE. It
// follows from the first: a live row is not eligible under `deleted(onOrBefore:)` but is still a
// referrer, so a live entry under a soft-deleted session holds that session in the store. The pass
// then does less than the caller asked and reports how much — which is recoverable, where
// hard-deleting the live entry to satisfy a tidier cascade would not be. `G-1.3` reserves hard
// deletion to this routine precisely because it is the one thing the app cannot undo. The cache is
// the one exception and the next paragraph is why. `everything` is not a second exception but a
// different question: it makes every row eligible, live ones included, and leaves nothing behind
// that could refer to anything — under it the clause is empty rather than broken.
//
// A CACHED DERIVED ROW IS NOT A REFERRER, AND THAT IS `G-1.4` RATHER THAN AN EXCEPTION. Counting
// one would let a `PersonalRecordCacheEntity` veto the removal of the set it was computed from —
// a derived value deciding the fate of the truth it was derived from, which is the inversion
// `G-1.4` exists to forbid. So the scan skips every ``CachedDerivedEntity``, and any cache row
// naming something this pass removes goes with it whatever its own state: `G-1.5`'s cache is
// rebuilt from logged sets, so removing an entry costs a recompute and keeping one would leave a
// personal record sourced from a set that no longer exists.
//
// THE EDGES ARE ENUMERATED IN `PurgePlan`, NOT DISCOVERED. There is no reflection over the schema
// that could find them — a join key is an ordinary `UUID` column and looks like `programRunID`,
// which names nothing in this phase at all. Adding an entity that carries a foreign key means
// adding it to that scan, and the compiler will not ask.

import Foundation

/// Which rows a purge is allowed to take (`TR-1.14`).
///
/// Two scopes rather than one parameterised cutoff, because ``everything`` is not "a cutoff of
/// `.distantFuture`": that would still spare every live row, and the wipe `DOD-1.3` verifies has to
/// leave the store empty. They differ only in which rows are eligible — the policy above is applied
/// identically to both, which is what makes the wipe a purge rather than a second routine beside
/// one.
public enum PurgeScope: Equatable, Sendable {
    /// Rows soft-deleted at or before `cutoff`, and nothing else.
    ///
    /// The bound is inclusive so that a cascade's rows, which all carry one timestamp, are eligible
    /// together — see ``SwiftDataWorkoutRepository/deleteSession(id:)``, which stamps a session and
    /// everything under it with the same `now`.
    case deleted(onOrBefore: Date)

    /// Every row in the store, live ones included — `DOD-1.3`'s wipe.
    ///
    /// **Not reachable from anything the lifter can tap** (see ``StorePurge``); it exists for the
    /// export → wipe → restore round trip and for a harness that needs a store it can trust to be
    /// empty.
    case everything

    /// Whether `row` is eligible under this scope.
    ///
    /// - Parameter row: The row.
    /// - Returns: `true` when the scope covers it.
    func covers(_ row: some StoredEntity) -> Bool {
        switch self {
        case .everything:
            return true
        case .deleted(let cutoff):
            guard let deletedAt = row.deletedAt else { return false }
            return deletedAt <= cutoff
        }
    }
}

/// What a purge did.
///
/// **``retained`` is the policy made visible, not an error count.** A pass that removes nothing and
/// retains twelve has found twelve eligible rows that something surviving still names, which is a
/// correct outcome and the only sign of it a caller gets; a pass that retains rows under
/// ``PurgeScope/everything`` has found a defect, since nothing survives that scope.
public struct PurgeReport: Equatable, Sendable {
    /// Rows hard-deleted from the store.
    public let removed: Int

    /// Rows the scope covered that a surviving row still named, and which are therefore still there.
    public let retained: Int

    /// Builds a report.
    ///
    /// - Parameters:
    ///   - removed: Rows hard-deleted.
    ///   - retained: Eligible rows held back.
    public init(removed: Int, retained: Int) {
        self.removed = removed
        self.retained = retained
    }
}
