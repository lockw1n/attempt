import Foundation
import PowerliftingCore
import RepositoryInterface

/// The Settings tab's landing screen, as state rather than as a view model (`TR-1.2`, `FR-1.10.1`).
///
/// **This type is the worked example of the pattern every Phase 1 screen follows.** The view owns
/// one of these in `@State`, this object owns the screen's data and every operation on it, and the
/// body only reads and calls. The property that makes it worth stating: nothing here needs a view
/// to run, so the screen's behaviour is tested by calling methods rather than by rendering.
///
/// It is **not** one of `TR-1.2`'s two stateful stores. The difference is lifetime and reach: this
/// lives exactly as long as the screen and speaks for it alone, where a store outlives any one
/// screen and is what several of them mutate through — see ``Logging/ActiveSessionStore``, the
/// first of the two.
///
/// **A failure never costs the screen its data**, and that is the third thing the pattern fixes.
/// The read's outcome and the last write's outcome are separate properties because they are
/// separate facts: a screen with no row cannot be shown, while a screen whose last write failed
/// still has everything it needs to let the user try again. Folding the two together makes one
/// transient save the end of the screen, since `@State` outlives every tab switch and push.
///
/// Storage is reached through ``RepositoryInterface/SettingsRepository`` and nothing else.
@Observable
public final class SettingsLandingState {
    /// What the screen has to show, as one value rather than three independent flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet. ``SettingsLandingState/load()`` moves out of this.
        case idle

        /// A read is in flight.
        case loading

        /// The settings row, as read or as last written.
        case loaded(UserSettings)

        /// The read failed, carrying the error's description.
        ///
        /// A **diagnostic**, not copy: it is not localized and a screen must not present it as a
        /// sentence written for the user (`G-3.4`). **Recoverable** — ``SettingsLandingState/load()``
        /// runs again from here, which is what gives the screen a retry.
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The last write that failed, as the error's description, or `nil` once one succeeds.
    ///
    /// A **diagnostic**, not copy (`G-3.4`). Deliberately not a ``Phase``: a failed write leaves
    /// the loaded row exactly where it was, so the screen keeps working and the next attempt is
    /// another tap rather than a relaunch.
    public private(set) var writeFailure: String?

    private let repository: any SettingsRepository

    /// The write chain. See ``setDisplayUnit(_:)``.
    private var pendingWrite: Task<Void, Never>?

    /// Builds the state over the repository it reads and writes through.
    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    /// Reads the settings row, on first appearance and on every retry.
    ///
    /// **Re-entrant only through ``Phase/loading``, and that is the reason it is a method and not
    /// an initializer.** SwiftUI runs `.task` again whenever the view's identity is re-established,
    /// and ``SettingsRepository``'s read is find-or-create — a second read is harmless, but a
    /// second one *in flight* would publish whichever finished last. A read that already succeeded
    /// is not repeated; one that failed is, which is the whole of the retry.
    public func load() async {
        switch phase {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        phase = .loading
        do {
            phase = .loaded(try await repository.settings())
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Switches which unit weights are displayed in (`G-3.1`, `FR-1.10.1`).
    ///
    /// Display only — storage stays in grams and no stored weight is rewritten (`G-3.2`).
    ///
    /// **Writes are serialized, and it is a correctness clause rather than a queueing nicety.**
    /// The decision below reads ``phase``, which only moves once the write it describes has landed;
    /// two overlapping calls would both decide against the same stale row, so the second would
    /// compare the user's newest choice against the value the first is in the middle of replacing
    /// and drop it. Chaining each write behind the one before it makes every decision read the
    /// result of the last.
    public func setDisplayUnit(_ unit: MassUnit) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.write(displayUnit: unit)
        }
        pendingWrite = write
        await write.value
    }

    /// One link of ``setDisplayUnit(_:)``'s chain: decide against the row as it stands now, then
    /// write.
    ///
    /// **A write is skipped when the unit is already `unit`**, and that too is a correctness clause
    /// rather than an optimisation: every save restamps `updatedAt`, which is `G-2.4`'s conflict
    /// key, so writing the value that is already there would let a local no-op outrank a real
    /// remote edit.
    private func write(displayUnit unit: MassUnit) async {
        guard case .loaded(let current) = phase, current.displayUnit != unit else { return }
        let updated = UserSettings(
            id: current.id,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            deletedAt: current.deletedAt,
            userID: current.userID,
            displayUnit: unit,
            e1RMFormula: current.e1RMFormula,
            theme: current.theme,
            defaultRoundingIncrement: current.defaultRoundingIncrement,
            defaultRoundingStrategy: current.defaultRoundingStrategy
        )
        do {
            try await repository.save(updated)
            // Re-read rather than publish `updated`: the save path stamps `updatedAt` itself, so
            // the record handed in describes the write before this one.
            phase = .loaded(try await repository.settings())
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
        }
    }
}
