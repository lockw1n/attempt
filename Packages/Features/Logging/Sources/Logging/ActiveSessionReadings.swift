import Foundation

/// What the workout in progress reads as, recomputed off the exercises it holds.
///
/// A file of its own rather than more of `ActiveSessionStore.swift`, which had reached SwiftLint's
/// length ceiling — `ActiveSessionCommands.swift`'s rule. Same type, same isolation.
extension ActiveSessionStore {
    /// Whether a workout is **held** — what every entry point reads.
    ///
    /// **Held, not in progress**, and the two differ for a planned day: ``endDay()`` keeps the
    /// finished row so the checklist can go on drawing it read-only, so this stays `true` after the
    /// day is over. A caller asking *"is the lifter still lifting"* wants ``isInProgress``.
    public var isActive: Bool { session != nil }

    /// Whether a workout has been started and not yet ended (`NFR-1.9`).
    ///
    /// **The screen-wake policy's reading, and the narrower of the two.** `NFR-1.9`'s "active"
    /// means started and not yet ended: before a planned day's first answer there is no row at all
    /// (`FR-17.9.5`) and the lifter is reading a plan, and after ``endDay()`` the row is still held
    /// but nobody is lifting. ``isActive`` is `true` across both of those, which is why the idle
    /// timer cannot key on it — held on every tab until the app is backgrounded, measured on the
    /// phone.
    public var isInProgress: Bool { session.map { $0.endedAt == nil } ?? false }

    /// How far through the workout the user is (`FR-1.2.13`).
    public var progress: SessionProgress { SessionProgress(exercises) }

    /// How much of what a routine prescribed has been performed as prescribed (`FR-15.3.3`), or
    /// `nil` for a workout nobody planned.
    ///
    /// **Recomputed off the held exercises on every read, like ``progress``**, which is what makes
    /// an adjustment show up in it for free: every command that changes a set ends in
    /// ``loadExercises()``, so the next read of this sees the corrected set with nothing to
    /// invalidate.
    public var adherence: SessionAdherence? { SessionAdherence(exercises) }
}
