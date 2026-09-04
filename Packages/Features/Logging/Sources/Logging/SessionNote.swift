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

    /// Takes the record a screen is holding, ignoring the states in which it holds none.
    ///
    /// **``follow(_:)`` with the empty case refused rather than obeyed**, and the two callers are
    /// what make it a separate method. A screen over the workout in progress has no record exactly
    /// when there is no workout, so emptying the field is right. A screen over one past session has
    /// no record for a second on *every re-read* — its phase passes through loading — and handed
    /// that gap the draft resets outright, so an edit typed and not yet saved is gone by the time
    /// the same session comes back: silently, and along with the ``hasUnsavedChanges`` that was the
    /// only sign of it.
    ///
    /// - Parameter session: The record the screen holds, or `nil` where it is between reads.
    mutating func follow(holding session: WorkoutSession?) {
        guard let session else { return }
        follow(session)
    }

    /// Puts the record's text back, discarding the edit.
    mutating func discard() { text = stored }

    /// The note's first line, for the folded header to show (`FR-16.6.1`) — empty when there is no
    /// note.
    ///
    /// **``text`` rather than ``stored``**, so what the header shows is what is on screen: a note
    /// typed and not yet saved is still the note this workout has, and a header quoting the stored
    /// text instead would fold away over an edit and show the version that edit replaced.
    ///
    /// **Split on newlines only, and never trimmed to a length.** Where the line ends on screen is
    /// the label's business — one `lineLimit` truncates for the width it actually has, in the
    /// locale's own way, where a character count here would cut mid-word at a width nothing here
    /// knows.
    var firstLine: String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? ""
    }
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

    /// Stores an unsaved note, then finishes the workout (`FR-1.2.9`, `FR-1.2.11`, `FR-16.6.1`).
    ///
    /// **This exists because the note moved next to Finish.** While the field sat at the top of the
    /// screen, a note typed and left unsaved was several screens away from the command that ends
    /// the workout, and losing it needed the user to scroll past **Save note** to reach **Finish**.
    /// Folded at the foot the two are adjacent, so tapping **Finish** over a dirty field is the
    /// ordinary path rather than a mistake, and silently dropping the text there would be the
    /// screen throwing away the last thing the user wrote.
    ///
    /// **The note is written first, and that order is not a preference.** ``writeNote(_:)``
    /// rebuilds the record from the one being held, and after ``finish()`` nothing is held — a note
    /// written second would be written against `nil` and dropped without a diagnostic.
    ///
    /// A failed note write still finishes the workout: the workout ending is the command the user
    /// asked for, the failure is reported where the note is, and a session left open because its
    /// prose did not store would be the smaller loss taking the larger one hostage.
    ///
    /// - Parameter note: What the field held when **Finish** was tapped, or `nil` where it held
    ///   nothing the record does not already have.
    func finish(saving note: String?) async {
        if let note { await saveNote(note) }
        await finish()
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
