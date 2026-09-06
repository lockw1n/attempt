import Foundation

/// What the workout in progress reads as, recomputed off the exercises it holds.
///
/// A file of its own rather than more of `ActiveSessionStore.swift`, which had reached SwiftLint's
/// length ceiling — `ActiveSessionCommands.swift`'s rule. Same type, same isolation.
extension ActiveSessionStore {
    /// Whether a workout is in progress — what the screen-wake policy and every entry point read.
    public var isActive: Bool { session != nil }

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
