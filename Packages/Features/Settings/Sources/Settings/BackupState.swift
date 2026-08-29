import Foundation
import RepositoryInterface

/// What the backup screen knows (`FR-1.11.3`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on ``HealthAccessState``'s rule: it is
/// read from this screen alone and lives exactly as long as it does.
///
/// **The file is written before it is offered, not when Share is tapped** — ``DataExportState``'s
/// reason: a share sheet needs a URL at the moment it is built, and a command that has to read the
/// whole store before it can hand anything over is a command that appears to do nothing for as long
/// as that takes. So the wait is on the way in, drawn.
@Observable
final class BackupState {
    /// What the screen has to show.
    ///
    /// **There is no empty case, and that is a decision rather than an omission.** The export has
    /// one because emptiness there is a question about the *log*, which a lifter can genuinely not
    /// have yet. A backup is a question about the *store*, and the store is never empty: the
    /// preferences row exists from the first read (`TR-1.10` mints it), the catalogue is seeded at
    /// first launch, and a gym or a custom exercise is the lifter's own work whether or not they
    /// have trained yet. A screen that refused to write a file because nothing had been *logged*
    /// would be refusing to back up exactly the configuration a clean install cannot rebuild.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// The store is being read and the file written. A real wait: it walks every table.
        case preparing

        /// The file exists and can be handed on.
        case ready(BackupFile)

        /// The read or the write failed. The payload is a diagnostic and is never drawn (`G-3.4`).
        case failed(String)
    }

    /// The screen's state.
    private(set) var phase: Phase = .idle

    /// The store this reads.
    @ObservationIgnored private let backup: FullBackup

    /// Where the file is written.
    @ObservationIgnored private let directory: URL

    /// When the backup is being taken. Injected so a test can pin the file name.
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Whether a preparation is already running.
    @ObservationIgnored private var isPreparing = false

    /// Builds the state over the store it backs up.
    ///
    /// - Parameters:
    ///   - backup: The store reader.
    ///   - directory: Where the file goes. Defaults to a directory of this app's own inside the
    ///     temporary one — the file is handed to the share sheet and is the system's to keep from
    ///     there, so nothing here belongs among the lifter's documents.
    ///   - now: When the backup is taken.
    init(
        backup: FullBackup,
        directory: URL = FileManager.default.temporaryDirectory.appending(path: "AttemptBackup"),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.backup = backup
        self.directory = directory
        self.now = now
    }

    /// Reads the store and writes the file.
    ///
    /// Single-flight, and it re-runs from any settled phase: the screen is pushed fresh each time,
    /// and the retry out of ``Phase/failed(_:)`` is the same call.
    func prepare() async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        phase = .preparing
        do {
            let archive = try await backup.archive(takenAt: now())
            phase = .ready(try BackupWriter.write(archive, into: directory))
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}

/// Which of the screen's states to draw — ``BackupState/Phase`` with the diagnostic dropped.
///
/// The same split ``DataExportScreenState`` makes, and for the same reason: a reference can be
/// rendered over one of these without a store behind it.
enum BackupScreenState: Equatable {
    /// The store has not been read yet.
    case preparing

    /// The file is ready.
    case ready(BackupFile)

    /// The backup could not be prepared.
    case failed

    /// Which state a phase is.
    ///
    /// - Parameter phase: The screen's state.
    /// - Returns: The state to draw.
    static func current(_ phase: BackupState.Phase) -> Self {
        switch phase {
        case .idle, .preparing: .preparing
        case .ready(let file): .ready(file)
        case .failed: .failed
        }
    }
}
