import DerivedValues
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

    /// What the app is told after a preference lands (`FR-1.10.2`, `NFR-1.9`).
    ///
    /// **Told rather than asked, and by closure rather than by store.** Two of this screen's
    /// preferences are read by objects in modules this one cannot import — the theme by the root
    /// view's own appearance store, the screen-wake by `Logging`'s — so the composition root
    /// supplies the one call that reaches both. Nothing re-reads this row on their behalf, so a
    /// picker that only wrote the column would leave the app on the old theme until the next
    /// relaunch.
    private let preferencesDidChange: (UserSettings) -> Void

    private let repository: any SettingsRepository

    /// The recompute pipeline, told when the formula moves (`FR-1.7.3`, `TR-1.6`).
    ///
    /// **Told rather than asked.** The actor holds the formula estimates are produced under and
    /// nothing re-reads this row on its behalf, so a picker that only wrote the column would leave
    /// every screen in the app showing estimates under the *old* formula until the next relaunch —
    /// which is `FR-1.7.3`'s "retroactively" not happening.
    private let records: PersonalRecordRecomputer

    /// The write chain. See ``setDisplayUnit(_:)``.
    private var pendingWrite: Task<Void, Never>?

    /// Builds the state over the repository it reads and writes through.
    ///
    /// - Parameters:
    ///   - repository: Where the settings row lives.
    ///   - records: The app's one recompute actor, told when a preference it reads moves.
    ///   - preferencesDidChange: What the app runs once a preference it holds elsewhere lands.
    public init(
        repository: any SettingsRepository,
        records: PersonalRecordRecomputer,
        preferencesDidChange: @escaping (UserSettings) -> Void = { _ in }
    ) {
        self.repository = repository
        self.records = records
        self.preferencesDidChange = preferencesDidChange
    }

    /// Reads the settings row, on first appearance and on every retry.
    ///
    /// **Re-entrant only through ``Phase/loading``, and that is the reason it is a method and not
    /// an initializer.** SwiftUI runs `.task` again whenever the view's identity is re-established,
    /// and ``RepositoryInterface/SettingsRepository``'s read is find-or-create — a second read is harmless, but a
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

    /// Moves one preference on the stored row (`FR-1.10.1`, `FR-1.10.2`).
    ///
    /// **One entry point for every control, and it takes the change rather than the row.** A
    /// screen with eight preferences on it and a setter each is eight chances to rebuild the row
    /// from a stale read; a control that handed back its own copy would be worse still, since the
    /// copy it is drawing was published before whatever write is in flight — the second of two
    /// rapid taps would then revert the first. A closure is applied to the row as it stands *inside*
    /// the chain, so it can only move the field it names.
    ///
    /// Display-only preferences never rewrite a stored weight — storage stays grams (`G-3.1`,
    /// `G-3.2`), and this method writes the settings row and nothing else.
    ///
    /// **Writes are serialized, and it is a correctness clause rather than a queueing nicety.**
    /// The decision below reads ``phase``, which only moves once the write it describes has landed;
    /// two overlapping calls would both decide against the same stale row, so the second would
    /// compare the user's newest choice against the value the first is in the middle of replacing
    /// and drop it. Chaining each write behind the one before it makes every decision read the
    /// result of the last.
    ///
    /// - Parameter change: What to move on the row.
    public func apply(_ change: @escaping (inout UserSettings) -> Void) async {
        await chained { [weak self] in await self?.write(change) }
    }

    /// Runs `operation` behind whatever write is already in flight. See ``apply(_:)``.
    private func chained(_ operation: @escaping () async -> Void) async {
        let previous = pendingWrite
        let write = Task {
            await previous?.value
            await operation()
        }
        pendingWrite = write
        await write.value
    }

    /// One link of the chain: decide against the row as it stands now, then write and announce.
    ///
    /// **A write is skipped when nothing moved**, and that is a correctness clause rather than an
    /// optimisation: every save restamps `updatedAt`, which is `G-2.4`'s conflict key, so writing
    /// the values that are already there would let a local no-op outrank a real remote edit.
    ///
    /// **The announcements come after the store, not before**, so a failed write leaves the app
    /// running under the preferences that are actually persisted. Each is made only where its own
    /// column moved: the recompute actor no-ops on a value already in force, but a `FR-1.7.3`
    /// recompute is expensive enough that "it would no-op" is not a reason to ask for one.
    private func write(_ change: (inout UserSettings) -> Void) async {
        guard case .loaded(let current) = phase else { return }
        var updated = current
        change(&updated)
        guard updated != current else { return }
        guard let stored = await save(updated) else { return }
        if stored.e1RMFormula != current.e1RMFormula {
            await records.formulaDidChange(to: stored.e1RMFormula)
        }
        if stored.e1RMLookbackDays != current.e1RMLookbackDays {
            await records.lookbackDidChange(to: E1RMLookback(days: stored.e1RMLookbackDays))
        }
        preferencesDidChange(stored)
    }

    /// Stores `updated`, then republishes what came back.
    ///
    /// - Returns: The stored row, or `nil` where the write failed.
    private func save(_ updated: UserSettings) async -> UserSettings? {
        do {
            try await repository.save(updated)
            // Re-read rather than publish `updated`: the save path stamps `updatedAt` itself, so
            // the record handed in describes the write before this one.
            let stored = try await repository.settings()
            phase = .loaded(stored)
            writeFailure = nil
            return stored
        } catch {
            writeFailure = String(describing: error)
            return nil
        }
    }
}
