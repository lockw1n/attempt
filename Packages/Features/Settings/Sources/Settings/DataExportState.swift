import Foundation
import PowerliftingCore
import RepositoryInterface

/// What the export screen knows (`FR-1.11.1`, `FR-1.11.2`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on ``HealthAccessState``'s rule: it is
/// read from this screen alone and lives exactly as long as it does.
///
/// **The files are written before either is offered, not when one is tapped.** A share sheet needs a
/// URL at the moment it is built, and a command that has to read the whole store before it can hand
/// anything over is a command that appears to do nothing for as long as that takes. So the wait is
/// where the wait belongs — on the way in, drawn.
@Observable
final class DataExportState {
    /// What the screen has to show.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// The log is being read and the files written. A real wait: it walks every session.
        case preparing

        /// Both files exist and can be handed on.
        case ready(TrainingLogExportFiles)

        /// There is no training log to export.
        case empty

        /// The read or the write failed. The payload is a diagnostic and is never drawn (`G-3.4`).
        case failed(String)
    }

    /// The screen's state.
    private(set) var phase: Phase = .idle

    /// The log this reads.
    @ObservationIgnored private let export: TrainingLogExport

    /// Where the CSV's unit comes from (`FR-1.10.1`).
    @ObservationIgnored private let settings: any SettingsRepository

    /// Where the files are written.
    @ObservationIgnored private let directory: URL

    /// When the export is being taken. Injected so a test can pin the file name.
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Whether a preparation is already running.
    @ObservationIgnored private var isPreparing = false

    /// Builds the state over the store it exports.
    ///
    /// - Parameters:
    ///   - export: The log reader.
    ///   - settings: The preferences row, read for the unit the CSV is written in.
    ///   - directory: Where the two files go. Defaults to a directory of this app's own inside the
    ///     temporary one — the files are handed to the share sheet and are the system's to keep from
    ///     there, so nothing here belongs among the lifter's documents.
    ///   - now: When the export is taken.
    init(
        export: TrainingLogExport,
        settings: any SettingsRepository,
        directory: URL = FileManager.default.temporaryDirectory.appending(path: "TrainingLogExport"),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.export = export
        self.settings = settings
        self.directory = directory
        self.now = now
    }

    /// Reads the log and writes both files.
    ///
    /// Single-flight, and it re-runs from any settled phase: the screen is pushed fresh each time,
    /// and the retry out of ``Phase/failed(_:)`` is the same call.
    func prepare() async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        phase = .preparing
        do {
            let archive = try await export.archive(exportedAt: now())
            guard !archive.isEmpty else {
                phase = .empty
                return
            }
            let unit = try await settings.settings().displayUnit
            phase = .ready(try TrainingLogExportWriter.write(archive, unit: unit, into: directory))
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}

/// Which of the screen's states to draw — ``DataExportState/Phase`` with the diagnostic dropped.
///
/// The same split ``HealthAccessScreenState`` makes, and for the same reason: a reference can be
/// rendered over one of these without a store behind it.
enum DataExportScreenState: Equatable {
    /// The log has not been read yet.
    case preparing

    /// Both files are ready.
    case ready(TrainingLogExportFiles)

    /// There is nothing logged to export.
    case empty

    /// The export could not be prepared.
    case failed

    /// Which state a phase is.
    ///
    /// - Parameter phase: The screen's state.
    /// - Returns: The state to draw.
    static func current(_ phase: DataExportState.Phase) -> Self {
        switch phase {
        case .idle, .preparing: .preparing
        case .ready(let files): .ready(files)
        case .empty: .empty
        case .failed: .failed
        }
    }
}
