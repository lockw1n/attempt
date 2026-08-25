import Foundation
import PowerliftingCore
import RepositoryInterface

/// One gym, projected into the type that loads a bar (`FR-1.4.1`, `FR-1.4.2`).
///
/// The record and the calculator travel together because the screen shows both: the arithmetic is
/// the calculator's, and the bar, the collars and the profile's name are the record's.
struct LoadedEquipment {
    /// The profile the loading is computed against.
    let profile: EquipmentProfile

    /// That profile's bar, collars and inventory, ready to load.
    let calculator: PlateCalculator

    /// Whether this is ``PlateCalculatorStore/interimProfile`` rather than a gym the user set up.
    ///
    /// The screen says so, because a plate list the user did not choose is a claim about their gym
    /// and an unattributed one would be read as a fact about it (`G-6.2`).
    let isInterim: Bool

    /// What to call this gym on screen.
    ///
    /// **Three cases and not two, because ``isInterim`` and an empty name are different facts.**
    /// The interim default carries no name *and* is not the user's, so it gets the catalogue's
    /// sentence saying as much. A profile the user configured and left unnamed is still theirs —
    /// nothing validates the name on the way in (`FR-1.4.2` owns the editor, and a restored or
    /// synced row reaches the store without one) — and answering it with the interim sentence would
    /// disclaim a gym they set up, which is the `G-6.2` attribution run backwards.
    var displayName: String {
        if isInterim { return String(localized: LoggingStrings.plateEquipmentInterim) }
        guard profile.name.isEmpty else { return profile.name }
        return String(localized: LoggingStrings.plateEquipmentUnnamed)
    }
}

/// Why the calculator has no equipment to load against.
///
/// **Two cases and not one string**, because they are opposite facts about whether asking again
/// could help: a read that failed may succeed on a retry, where a profile whose plate lists cannot
/// describe a gym will refuse identically every time and is fixed by editing it (T-1.31).
enum PlateEquipmentFailure: Error, Equatable {
    /// The profile could not be read. The value is the error's description — a diagnostic, not copy
    /// (`G-3.4`).
    case readFailed(String)

    /// A profile was read and cannot be used: its two plate lists disagree, repeat a denomination,
    /// or multiply out past `Int`. The value is a diagnostic.
    case unusable(String)
}

/// The equipment the plate calculator loads against, read once and held for the app's lifetime
/// (`TR-1.2`).
///
/// **A store rather than a screen's own state, on ``ActiveSessionStore``'s rule: lifetime, not
/// complexity.** Which gym is active outlives every surface that shows a loading — the row inside
/// the set editor, the calculator presented over it, and T-1.31's profile editor in another tab —
/// and all three read the same fact. Two objects would be two answers to *which gym is this*.
///
/// **The interim default is this layer's and never the repository's.** `EquipmentRepository`
/// answers `nil` for a user who has configured no gym and invents nothing, deliberately, because a
/// bar and plate set written into the store would be a data claim `G-6.2` wants cited and a row
/// nobody authored. What this type supplies instead is a *display* fallback: nothing is written, the
/// screen labels it as not-yours, and T-1.31 deletes it the moment a profile can be authored.
@Observable
public final class PlateCalculatorStore {
    /// The gym currently loaded against, or `nil` before the first read and after a failed one.
    private(set) var equipment: LoadedEquipment?

    /// Why there is none, or `nil`.
    private(set) var failure: PlateEquipmentFailure?

    /// Whether the profile has been read yet.
    ///
    /// The difference between "no equipment" and "not asked yet", which ``equipment`` alone cannot
    /// carry — ``ActiveSessionStore/hasCheckedForSession``'s argument, one screen along.
    private(set) var hasLoaded = false

    @ObservationIgnored private let repository: any EquipmentRepository

    /// Builds the store over the profile repository.
    ///
    /// - Parameter repository: Where the user's equipment profiles live.
    public init(repository: any EquipmentRepository) {
        self.repository = repository
    }

    /// Reads the active profile and projects it, falling back to ``interimProfile``.
    ///
    /// Re-read rather than cached-once, so a profile edited in another tab reaches the next loading
    /// without the app being relaunched. The read is local and synchronous underneath (`G-2.3`), so
    /// what a second one costs is a store hit.
    func load() async {
        do {
            let stored = try await repository.defaultProfile()
            equipment = try Self.project(stored ?? Self.interimProfile, isInterim: stored == nil)
            failure = nil
        } catch let error as PlateEquipmentFailure {
            equipment = nil
            failure = error
        } catch {
            equipment = nil
            failure = .readFailed(String(describing: error))
        }
        hasLoaded = true
    }

    /// What `target` loads to on the equipment currently held (`FR-1.4.1`, `FR-1.4.4`).
    ///
    /// - Parameter target: The weight wanted on the bar.
    /// - Returns: The result, or `nil` when there is no equipment to load against — which is the
    ///   states above rather than an answer.
    func loading(for target: Weight) -> PlateLoadingResult? {
        equipment?.calculator.loading(for: target)
    }

    /// Projects one profile, turning both refusals into ``PlateEquipmentFailure/unusable(_:)``.
    ///
    /// **The interim default goes through this same path**, which is what keeps it from needing a
    /// branch that cannot be reached: `PlateInventory` and `PlateCalculator` both refuse, both
    /// refusals already have a state, and a hand-built profile that stopped being loadable would
    /// say so on screen instead of being force-unwrapped into a crash.
    ///
    /// - Parameters:
    ///   - profile: The record to project.
    ///   - isInterim: Whether it is the interim default.
    /// - Returns: The gym, ready to load.
    /// - Throws: ``PlateEquipmentFailure/unusable(_:)``.
    private static func project(
        _ profile: EquipmentProfile,
        isInterim: Bool
    ) throws -> LoadedEquipment {
        let inventory: PlateInventory
        do {
            inventory = try profile.inventory()
        } catch {
            throw PlateEquipmentFailure.unusable(String(describing: error))
        }
        guard
            let calculator = PlateCalculator(
                bar: profile.barWeight, collar: profile.collarWeight, inventory: inventory)
        else {
            throw PlateEquipmentFailure.unusable("bar, collars and inventory overflow")
        }
        return LoadedEquipment(profile: profile, calculator: calculator, isInterim: isInterim)
    }

    /// The gym assumed until the user sets one up — a 20 kg bar, 2.5 kg collars and a metric
    /// competition plate set.
    ///
    /// **Never written to the store, and its identifier is therefore disposable.** It exists to give
    /// `FR-1.4.1` an answer on first launch rather than a blank screen, and T-1.31 replaces it with
    /// a profile the user authored. Its ``EquipmentProfile/name`` is deliberately empty: a name is a
    /// user's word for their gym, and copy for this one belongs in the catalogue with the rest
    /// (`G-3.4`), not in a record.
    ///
    /// **Metric, and that is a choice rather than a default.** The denominations of a pound gym are
    /// not the kilo ones converted; picking one set means picking a gym, so the screen says which it
    /// picked. Loads are still drawn in the user's display unit (`G-3.1`).
    static let interimProfile = EquipmentProfile(
        id: UUID(),
        createdAt: .distantPast,
        updatedAt: .distantPast,
        deletedAt: nil,
        name: "",
        barWeight: Weight(grams: 20_000),
        collarWeight: Weight(grams: 2_500),
        plates: [25_000, 20_000, 15_000, 10_000, 5_000, 2_500, 1_250].map(Weight.init(grams:)),
        platePairCounts: [4, 1, 1, 1, 1, 1, 1],
        isDefault: false
    )
}

/// Which of `FR-1.13.1`'s states the calculator screen is in.
///
/// A resolver rather than a chain of `if let` inside the view, for the reason every screen in this
/// module states: which state was chosen is a unit test's question, and what it looks like is a
/// snapshot's.
enum PlateEquipmentState: Equatable {
    /// Nothing has looked for a profile yet.
    case loading

    /// A gym is loaded and the target can be answered.
    case ready

    /// The profile could not be read; a retry may work.
    case readFailed

    /// A profile was read and cannot describe a gym; a retry would refuse identically.
    case unusable

    /// Which state a store is in.
    ///
    /// **`hasLoaded` outranks everything**, so the screen does not report "cannot be read" for the
    /// frame before the read answers.
    ///
    /// - Parameters:
    ///   - hasLoaded: Whether the read has answered.
    ///   - hasEquipment: Whether a gym came back.
    ///   - failure: Why one did not.
    /// - Returns: The state to draw.
    static func current(
        hasLoaded: Bool,
        hasEquipment: Bool,
        failure: PlateEquipmentFailure?
    ) -> Self {
        guard hasLoaded else { return .loading }
        if hasEquipment { return .ready }
        switch failure {
        case .unusable: return .unusable
        // A read that answered with neither equipment nor a diagnostic is not a state this store
        // can produce — `load()` sets one or the other — and reporting it as a failed read is the
        // one of the four that offers the user a way out of it.
        case .readFailed, nil: return .readFailed
        }
    }
}
