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

    /// What to call this gym on screen — ``EquipmentProfileSummary/name(of:)``'s answer, so the
    /// calculator and the screen that named the gym cannot call it two different things.
    var displayName: String { EquipmentProfileSummary.name(of: profile) }
}

/// Why the calculator has no equipment to load against.
///
/// **Two cases and not one string**, because they are opposite facts about whether asking again
/// could help: a read that failed may succeed on a retry, where a profile whose plate lists cannot
/// describe a gym will refuse identically every time and is fixed by editing it.
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
/// the set editor, the calculator presented over it, and the equipment editor in another tab —
/// and all three read the same fact. Two objects would be two answers to *which gym is this*.
///
/// **A user with no gym gets no equipment, and that is a state rather than a fallback.**
/// `EquipmentRepository` answers `nil` for a lifter who has configured nothing and invents nothing,
/// deliberately: a bar and plate set this app chose would be a data claim `G-6.2` wants cited and a
/// row nobody authored. The screen says there is no gym and offers the one tap that makes one.
@Observable
public final class PlateCalculatorStore {
    /// The gym currently loaded against, or `nil` before the first read, after a failed one, and
    /// for a lifter who has set none up.
    private(set) var equipment: LoadedEquipment?

    /// Why there is none, or `nil`.
    private(set) var failure: PlateEquipmentFailure?

    /// Whether the profile has been read yet.
    ///
    /// The difference between "no equipment" and "not asked yet", which ``equipment`` alone cannot
    /// carry — ``ActiveSessionStore/hasCheckedForSession``'s argument, one screen along.
    private(set) var hasLoaded = false

    /// The unit every weight on the equipment screens is entered and drawn in (`G-3.1`).
    ///
    /// **Read here rather than passed in**, on ``ActiveSessionStore/displayUnit``'s argument: the
    /// preference is one settings row, and a screen handed a unit by whichever surface opened it
    /// would show kilograms from one entry point and pounds from the other. A failed read leaves it
    /// as it was — the preference is not what this screen is about, and refusing to draw a gym
    /// because a settings row could not be read would be the wrong failure.
    private(set) var displayUnit: MassUnit = .kilograms

    /// Where the profiles live.
    ///
    /// **Readable inside this module**, because `FR-1.4.3`'s switcher is reachable from the
    /// calculator this store feeds: the screen it opens writes through the same repository, and this
    /// store's next ``load()`` is what picks the change up. A second repository handed in beside
    /// this one would be a second answer to *which store is this*.
    @ObservationIgnored let repository: any EquipmentRepository

    /// Where ``displayUnit`` is read from.
    @ObservationIgnored private let settings: any SettingsRepository

    /// Builds the store over the two rows a loading is drawn from.
    ///
    /// - Parameters:
    ///   - repository: Where the user's equipment profiles live.
    ///   - settings: Where the display unit lives (`G-3.1`).
    public init(repository: any EquipmentRepository, settings: any SettingsRepository) {
        self.repository = repository
        self.settings = settings
    }

    /// Reads the active profile and projects it.
    ///
    /// Re-read rather than cached-once, so a profile edited in another tab reaches the next loading
    /// without the app being relaunched. The read is local and synchronous underneath (`G-2.3`), so
    /// what a second one costs is a store hit.
    ///
    /// **No profile is not a failure**, and the two are kept apart: ``failure`` stays `nil` and
    /// ``equipment`` is `nil`, which is the pair ``PlateEquipmentState`` reads as "no gym set up".
    func load() async {
        if let unit = try? await settings.settings().displayUnit {
            displayUnit = unit
        }
        do {
            let stored = try await repository.defaultProfile()
            equipment = try stored.map(Self.project)
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
    /// - Parameter profile: The record to project.
    /// - Returns: The gym, ready to load.
    /// - Throws: ``PlateEquipmentFailure/unusable(_:)``.
    private static func project(_ profile: EquipmentProfile) throws -> LoadedEquipment {
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
        return LoadedEquipment(profile: profile, calculator: calculator)
    }
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

    /// The read answered and the user has configured no gym — `FR-1.13.1`'s empty state, whose
    /// action is the only thing that produces one.
    case noEquipment

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
        case .readFailed: return .readFailed
        // Neither equipment nor a diagnostic is the ordinary answer for a lifter who has set up no
        // gym — `defaultProfile()` returns `nil` and invents nothing — so it is an empty state and
        // not a failure. Reporting it as a failed read would offer a retry that answers the same
        // way every time, in place of the one tap that fixes it.
        case nil: return .noEquipment
        }
    }
}
