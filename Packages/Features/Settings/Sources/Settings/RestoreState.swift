import Foundation

/// What the restore screen knows (`FR-1.11.4`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on ``HealthAccessState``'s rule: it is
/// read from this screen alone and lives exactly as long as it does.
///
/// **The file is read and understood before the confirmation is offered, not after it is given.**
/// The opposite order would put the destructive question in front of a lifter over a file that turns
/// out to be an export, or a file from a newer build — and having said yes to *replace everything*,
/// they would then be told the file was no good. So the refusals happen first, and what the
/// confirmation is asked about is a file already known to be readable and already counted.
@Observable
final class RestoreState {
    /// What the screen has to show.
    ///
    /// **Seven cases for one command, because a restore is two decisions with a wait either side.**
    /// Picking the file and agreeing to overwrite are separate acts by construction — that is
    /// `FR-1.11.4`'s "cannot be bypassed accidentally" expressed as a type rather than as a
    /// convention a view could quietly break.
    ///
    /// ``refused(_:)`` and ``failed(_:)`` are two states and not one: a refusal wrote nothing and
    /// carries a sentence for the lifter, and a failure stopped part-way and carries a diagnostic.
    enum Phase: Equatable {
        /// No file has been chosen.
        case waiting

        /// A file is being read and checked.
        case reading

        /// The file is understood, and the destructive question has not been answered.
        case confirming(BackupSummary)

        /// The rows are being written. A real wait: it walks every section.
        case restoring

        /// Every row in the file has been written.
        case restored(BackupSummary)

        /// The file cannot be used, and nothing was written.
        case refused(RestoreRefusal)

        /// A write failed part-way. The payload is a diagnostic and is never drawn (`G-3.4`).
        case failed(String)
    }

    /// The screen's state.
    private(set) var phase: Phase = .waiting

    /// The store this writes into.
    @ObservationIgnored private let restore: StoreRestore

    /// The file the confirmation is about.
    ///
    /// **Held rather than re-read on confirmation**, which is what makes the two taps one decision
    /// about one file: re-reading would let a file replaced on disk between the counts and the
    /// answer be the file that actually landed.
    @ObservationIgnored private var pending: TrainingLogArchive?

    /// Whether a read or a write is already running.
    @ObservationIgnored private var isBusy = false

    /// Builds the state over the store it restores into.
    ///
    /// - Parameter restore: The writer.
    init(restore: StoreRestore) {
        self.restore = restore
    }

    /// Reads the chosen file and either counts it or refuses it.
    ///
    /// **The security-scoped access is released whichever way the read goes.** A URL from
    /// `fileImporter` is outside this app's container, and one that stayed claimed would hold a
    /// coordination scope open for as long as the screen lives.
    ///
    /// Single-flight, on ``BackupState``'s rule.
    ///
    /// - Parameter url: The file the lifter chose.
    func read(_ url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        phase = .reading
        pending = nil
        do {
            let archive = try Self.archive(at: url)
            pending = archive
            phase = .confirming(BackupSummary(archive))
        } catch let refusal as RestoreRefusal {
            phase = .refused(refusal)
        } catch {
            // Anything the file system raised — the file moved, or the scope was denied. Unreadable
            // is the lifter's reading of both, and the sentence under it says to try the file again.
            phase = .refused(.unreadable)
        }
    }

    /// Writes the file that was counted.
    ///
    /// **It does nothing unless a file is pending**, so a confirmation cannot arrive for a screen
    /// that has been reset back to ``Phase/waiting`` — the answer belongs to the question it was
    /// asked about.
    ///
    /// Single-flight, so a double tap on the destructive button writes the file once.
    func confirmRestore() async {
        guard !isBusy, let archive = pending else { return }
        isBusy = true
        defer { isBusy = false }
        phase = .restoring
        do {
            phase = .restored(try await restore.restore(archive))
            pending = nil
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Puts the screen back to where it started, for a lifter who wants a different file.
    ///
    /// **It clears the pending archive too.** Leaving one behind would make ``confirmRestore()``
    /// able to write a file the screen has stopped showing.
    func chooseAnother() {
        guard !isBusy else { return }
        pending = nil
        phase = .waiting
    }

    /// The bytes behind a picked URL, checked.
    ///
    /// - Parameter url: The file.
    /// - Returns: The archive.
    /// - Throws: A ``RestoreRefusal``, or whatever reading the file raised.
    private static func archive(at url: URL) throws -> TrainingLogArchive {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try StoreRestore.archive(from: try Data(contentsOf: url))
    }
}

/// Which of the screen's states to draw — ``RestoreState/Phase`` with the diagnostic dropped.
///
/// The same split ``BackupScreenState`` makes, and for the same reason: a reference can be rendered
/// over one of these without a store behind it.
///
/// **The refusal survives the split where the failure's diagnostic does not**, because the two are
/// not the same kind of payload: ``RestoreRefusal`` is a choice between three sentences written for
/// the lifter, and ``RestoreState/Phase/failed(_:)``'s string is an error's description (`G-3.4`).
enum RestoreScreenState: Equatable {
    /// No file has been chosen.
    case waiting

    /// The file is being read.
    case reading

    /// The destructive question, over what the file holds.
    case confirming(BackupSummary)

    /// The rows are being written.
    case restoring

    /// They were.
    case restored(BackupSummary)

    /// The file cannot be used.
    case refused(RestoreRefusal)

    /// A write failed part-way.
    case failed

    /// Which state a phase is.
    ///
    /// - Parameter phase: The screen's state.
    /// - Returns: The state to draw.
    static func current(_ phase: RestoreState.Phase) -> Self {
        switch phase {
        case .waiting: .waiting
        case .reading: .reading
        case .confirming(let summary): .confirming(summary)
        case .restoring: .restoring
        case .restored(let summary): .restored(summary)
        case .refused(let refusal): .refused(refusal)
        case .failed: .failed
        }
    }
}
