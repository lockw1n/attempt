import Foundation
import PowerliftingCore
import RepositoryInterface

/// The equipment screen's data and every operation on it (`FR-1.4.2`, `FR-1.4.3`, `FR-1.10.3`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on `SettingsLandingState`'s rule —
/// lifetime and reach. Which gym is active outlives every screen and is ``PlateCalculatorStore``'s;
/// the list of gyms and the form over one of them live exactly as long as this screen does.
///
/// **A failure never costs the screen its data.** The read's outcome and the last write's outcome
/// are separate properties because they are separate facts: a screen with no list cannot be shown,
/// while a screen whose last write failed still has everything it needs to let the user try again.
///
/// **Which profile is active is read from the repository rather than derived from the rows.** Two
/// rows can both carry ``RepositoryInterface/EquipmentProfile/isDefault`` — a store this app did
/// not write is allowed to disagree with itself — and
/// ``RepositoryInterface/EquipmentRepository/defaultProfile()`` is where that tie is broken.
/// Deriving the badge here instead would put a second copy of that rule on a screen, and the two
/// would be free to disagree about which gym the calculator is actually loading against.
@Observable
final class EquipmentProfilesState {
    /// What the screen has to show, as one value rather than three flags.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// A read is in flight.
        case loading

        /// Every profile the user has, in name order (`FR-1.10.3`).
        case loaded([EquipmentProfile])

        /// The read failed, carrying the error's description — a **diagnostic**, not copy
        /// (`G-3.4`). Recoverable: ``load()`` runs again from here, which is the retry.
        case failed(String)
    }

    /// The screen's read state.
    private(set) var phase: Phase = .idle

    /// Which profile the plate calculator reaches for, or `nil` when none is marked.
    private(set) var activeProfileID: UUID?

    /// The gyms the last read returned, or none while it has not answered.
    ///
    /// A read-through of ``phase`` rather than a second stored property: two would be two answers to
    /// what the screen is showing, and the one that was not updated would be the one drawn.
    var profiles: [EquipmentProfile] {
        guard case .loaded(let profiles) = phase else { return [] }
        return profiles
    }

    /// The last write that failed, as the error's description, or `nil` once one succeeds. A
    /// **diagnostic**, not copy (`G-3.4`).
    private(set) var writeFailure: String?

    @ObservationIgnored private let repository: any EquipmentRepository

    /// Builds the state over the repository it reads and writes through.
    ///
    /// - Parameter repository: Where the user's equipment profiles live.
    init(repository: any EquipmentRepository) {
        self.repository = repository
    }

    /// Reads every profile and which one is active.
    ///
    /// **Re-read on every appearance rather than once**, which is the opposite of
    /// `SettingsLandingState`'s rule and for the opposite reason: that screen's read is
    /// find-or-create, where this one is a list two other surfaces can add to. Only a read already
    /// in flight is skipped, so nothing publishes over a newer answer.
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        do {
            let profiles = try await repository.profiles(includingDeleted: false)
            activeProfileID = try await repository.defaultProfile()?.id
            phase = .loaded(profiles)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Writes a profile — `FR-1.4.2`'s create and edit in one operation.
    ///
    /// **A profile saved while no gym is active becomes the active one**, and that clause is what
    /// makes the first one usable. ``RepositoryInterface/EquipmentRepository/save(_:)`` deliberately does not honour
    /// ``RepositoryInterface/EquipmentProfile/isDefault``, so without this the very first gym a user sets up would be
    /// stored and then loaded against by nothing. It fires only when there is no default at all: a
    /// second profile must not quietly take over from the one in use.
    ///
    /// - Parameters:
    ///   - draft: The form's contents.
    ///   - existing: The profile being edited, or `nil` when this is a new one.
    /// - Returns: Whether the write landed. `false` leaves the form open over ``writeFailure``.
    @discardableResult
    func save(_ draft: EquipmentProfileDraft, replacing existing: EquipmentProfile?) async -> Bool {
        guard let profile = draft.profile(replacing: existing) else { return false }
        do {
            try await repository.save(profile)
            if try await repository.defaultProfile() == nil {
                try await repository.makeDefault(profileID: profile.id)
            }
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
            return false
        }
        await reload()
        return true
    }

    /// Retires the last failure.
    ///
    /// **Called when a form opens**, because ``writeFailure`` outlives the operation that set it:
    /// a switch that failed on the list would otherwise be the first thing a freshly opened editor
    /// reported, over a form the user has not yet saved and about a gym they were not editing.
    func clearWriteFailure() {
        writeFailure = nil
    }

    /// Switches which gym every loading is worked out on (`FR-1.4.3`).
    ///
    /// - Parameter profileID: The profile to make active.
    func makeActive(_ profileID: UUID) async {
        await write { try await $0.makeDefault(profileID: profileID) }
    }

    /// Soft-deletes a profile (`G-1.3`).
    ///
    /// **Deleting the active gym leaves none active rather than promoting another**, which is the
    /// repository's decision and is deliberately not repaired here: which gym a lifter uses next is
    /// not derivable from the rows, the calculator degrades to saying it has no equipment, and the
    /// way out is one tap on this screen.
    ///
    /// - Parameter profileID: The profile to delete.
    func delete(_ profileID: UUID) async {
        await write { try await $0.deleteProfile(id: profileID) }
    }

    /// One mutation, then the re-read that publishes its result.
    ///
    /// - Parameter mutation: What to run against the repository.
    private func write(_ mutation: (any EquipmentRepository) async throws -> Void) async {
        do {
            try await mutation(repository)
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
            return
        }
        await reload()
    }

    /// A read that is not skipped by an in-flight one, for use straight after a write.
    private func reload() async {
        phase = .idle
        await load()
    }
}

/// Which of `FR-1.13.1`'s states the equipment screen is in.
///
/// A resolver rather than a chain of `if let` inside the view, for the reason every screen in this
/// module states: which state was chosen is a unit test's question, and what it looks like is a
/// snapshot's.
enum EquipmentProfilesScreenState: Equatable {
    /// The list has not been read yet.
    case loading

    /// The read answered and the user has no gyms — `FR-1.13.2`'s first-launch case, whose action is
    /// the only way to make one.
    case empty

    /// There are profiles to show.
    case ready

    /// The list could not be read; a retry may work.
    case failed

    /// Which state a phase is.
    ///
    /// - Parameter phase: The screen's read state.
    /// - Returns: The state to draw.
    static func current(_ phase: EquipmentProfilesState.Phase) -> Self {
        switch phase {
        case .idle, .loading: .loading
        case .loaded(let profiles): profiles.isEmpty ? .empty : .ready
        case .failed: .failed
        }
    }
}
