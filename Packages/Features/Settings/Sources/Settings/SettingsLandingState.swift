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
/// Storage is reached through ``RepositoryInterface/SettingsRepository`` and nothing else.
@Observable
public final class SettingsLandingState {
    /// What the screen has to show, as one value rather than four independent flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet. ``SettingsLandingState/load()`` moves out of this exactly once.
        case idle

        /// A read is in flight.
        case loading

        /// The settings row, as read or as last written.
        case loaded(UserSettings)

        /// The read or the write failed, carrying the error's description.
        ///
        /// A **diagnostic**, not copy: it is not localized and a screen must not present it as a
        /// sentence written for the user (`G-3.4`).
        case failed(String)
    }

    /// The screen's whole visible state.
    public private(set) var phase: Phase = .idle

    private let repository: any SettingsRepository

    /// Builds the state over the repository it reads and writes through.
    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    /// Reads the settings row, on first appearance.
    ///
    /// **Idempotent, and that is the reason it is a method and not an initializer.** SwiftUI runs
    /// `.task` again whenever the view's identity is re-established, and ``SettingsRepository``'s
    /// read is find-or-create — a second read is harmless, but a second one *in flight* would
    /// publish whichever finished last.
    public func load() async {
        guard phase == .idle else { return }
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
    /// **A write is skipped when the unit is already `unit`**, and that is a correctness clause
    /// rather than an optimisation: every save restamps `updatedAt`, which is `G-2.4`'s conflict
    /// key, so writing the value that is already there would let a local no-op outrank a real
    /// remote edit.
    public func setDisplayUnit(_ unit: MassUnit) async {
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
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
