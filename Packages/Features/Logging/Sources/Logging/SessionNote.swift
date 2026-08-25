import Foundation
import RepositoryInterface

/// What is in `FR-1.2.9`'s session-note field, and what is stored behind it.
///
/// **The draft is the screen's, not the store's.** ``ActiveSessionStore`` holds what outlives a
/// screen; half-typed text is the other kind of state, alongside which cards are folded and what is
/// half-entered in the set editor. Held as a value so the one rule with any content in it — when
/// the field gives way to the record — can be asserted without a store or a rendering behind it.
///
/// **Not the per-set note** (`FR-1.2.3`), which is a field of ``SetDraft`` and belongs to one set.
/// This is prose about the workout.
struct SessionNoteDraft: Equatable, Sendable {
    /// Which workout this draft belongs to, or `nil` before one has been read.
    private(set) var sessionID: UUID?

    /// What is in the field. The user's, and the only property they move.
    var text: String = ""

    /// What the record said when it was last read — what ``text`` is compared against, and what
    /// ``discard()`` puts back.
    private(set) var stored: String = ""

    /// Whether the field differs from the record. What shows the two commands, and what a write has
    /// to be asked for.
    var hasUnsavedChanges: Bool { text != stored }

    /// Takes the workout the store is now holding.
    ///
    /// **A different workout replaces the draft outright**, including one being typed: a note is
    /// prose about a particular session, and carrying it into the next one would put words the user
    /// wrote about Tuesday into Thursday's record.
    ///
    /// **The same workout, re-read, keeps an unsaved edit.** Every appearance of the screen re-reads
    /// the session, and a read that overwrote the field would drop whatever had been typed since —
    /// silently, and along with the ``hasUnsavedChanges`` that was the only sign of it. The field
    /// gives way only where it still agrees with the record, which is what makes a note saved on
    /// another surface show up here.
    ///
    /// **No workout empties it**, for the first rule's reason: there is nothing for the text to be
    /// about.
    ///
    /// - Parameter session: The workout the store holds, or `nil`.
    mutating func follow(_ session: WorkoutSession?) {
        guard let session else {
            self = SessionNoteDraft()
            return
        }
        guard session.id == sessionID else {
            self = SessionNoteDraft(sessionID: session.id, text: session.notes, stored: session.notes)
            return
        }
        let hadUnsavedChanges = hasUnsavedChanges
        stored = session.notes
        if !hadUnsavedChanges { text = session.notes }
    }

    /// Puts the record's text back, discarding the edit.
    mutating func discard() { text = stored }
}

/// `FR-1.2.9`'s write. A file of its own on ``ActiveSessionCommands``' argument.
extension ActiveSessionStore {
    /// Stores the workout's session note (`FR-1.2.9`, `NFR-1.8`).
    ///
    /// **Serialized behind every other command**, on the chain's own rule and for a sharper reason
    /// here than most: this write rebuilds the whole session record from the one being held, so a
    /// note save overlapping ``finish()`` would store the workout as it was before it ended and put
    /// `endedAt` back to `nil`.
    ///
    /// - Parameter text: What the field held when **Save** was tapped. Taken then rather than read
    ///   at write time, so what is stored is what was on screen when it was asked for — see the
    ///   caller.
    func saveNote(_ text: String) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeNote(text)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``saveNote(_:)``.
    ///
    /// **Text the record already carries is not written**, and neither is anything at all when no
    /// workout is held: every save restamps `updatedAt`, which is `G-2.4`'s conflict key, so a local
    /// no-op would outrank a real remote edit. Either way the diagnostic is retired — nothing is
    /// outstanding.
    ///
    /// - Parameter text: The text to store.
    fileprivate func writeNote(_ text: String) async {
        guard let current = session, current.notes != text else {
            noteWriteFailure = nil
            return
        }
        do {
            try await persist(Self.noted(current, as: text))
            noteWriteFailure = nil
        } catch {
            // The held workout is left alone and so is the field: nothing reached the store, so the
            // retry is another tap at the same command rather than a note the user has to retype.
            noteWriteFailure = String(describing: error)
        }
    }

    /// `session` with its note replaced and every other field untouched.
    ///
    /// Rebuilt rather than mutated, the record being a value with `let` properties; the three
    /// timestamps are carried across because the write path is an upsert that stamps `updatedAt`
    /// itself.
    ///
    /// - Parameters:
    ///   - session: The workout.
    ///   - text: Its new note.
    /// - Returns: The record to store.
    private static func noted(_ session: WorkoutSession, as text: String) -> WorkoutSession {
        WorkoutSession(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            deletedAt: session.deletedAt,
            date: session.date,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            notes: text,
            bodyweight: session.bodyweight,
            programRunID: session.programRunID,
            scheduledWorkoutID: session.scheduledWorkoutID
        )
    }
}
