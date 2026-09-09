import Foundation
import PowerliftingCore
import RepositoryInterface

/// What `FR-1.6.5`'s feed is narrowed to (`FR-16.3.1`, `FR-17.3.2`, `FR-16.3.4`).
///
/// **Resolved identifiers rather than the stored scope**, and that is this type's whole reason for
/// existing. `RecentRecordsScope.dashboardLifts` means "whatever `FR-1.9.1` currently selects",
/// which is a rule about a *catalogue* — a lifter who has never opened the picker gets the three
/// competition lifts, resolved by name against the rows that are actually installed. That rule lives
/// in the dashboard feature, one layer up, so the caller resolves it and hands this the answer.
///
/// **Applied after grouping, never before.** A run is one feed entry labelled by its own scheme
/// (`FR-17.2.1`), so a filter on schemes has to see the label — filtering the cached cells first
/// would drop the very rows a run's cell is chosen from and relabel the event.
public struct RecentRecordsFilter: Sendable, Hashable {
    /// The exercises to report on, or `nil` for every one of them.
    ///
    /// **`nil` and not an empty set for "everything"**: `[]` is a lifter who chose the narrow scope
    /// and then ticked nothing, which is an empty feed they asked for.
    public let exerciseIDs: Set<UUID>?

    /// Which schemes appear (`FR-17.3.2`).
    public let schemes: RecentRecordsSchemes

    /// Whether a scheme's first-ever record appears (`FR-16.3.4`).
    public let showsBaselines: Bool

    /// Builds a filter.
    ///
    /// - Parameters:
    ///   - exerciseIDs: The exercises, already resolved, or `nil` for all.
    ///   - schemes: The scheme rule.
    ///   - showsBaselines: Whether baselines are drawn.
    public init(
        exerciseIDs: Set<UUID>?,
        schemes: RecentRecordsSchemes,
        showsBaselines: Bool
    ) {
        self.exerciseIDs = exerciseIDs
        self.schemes = schemes
        self.showsBaselines = showsBaselines
    }

    /// The feed as it was before `FR-16.3` configured it: every exercise, every scheme, baselines
    /// included.
    ///
    /// The default a caller with no settings row to read gets — and what keeps
    /// ``PersonalRecordRecomputer/recentRecords(limit:filter:)`` answering the same thing its
    /// unfiltered predecessor did.
    public static let unfiltered = Self(
        exerciseIDs: nil, schemes: .everyScheme, showsBaselines: true)

    /// The same filter with only `FR-16.3.1`'s scope narrowed — every scheme, baselines included.
    ///
    /// What a configuration screen reads to find out which schemes are *available* to choose among:
    /// the answer is the distinct maximal schemes the scope's own records carry, which is a question
    /// about the scope alone.
    ///
    /// - Parameter exerciseIDs: The exercises, or `nil` for all.
    /// - Returns: The filter.
    public static func scoped(to exerciseIDs: Set<UUID>?) -> Self {
        Self(exerciseIDs: exerciseIDs, schemes: .everyScheme, showsBaselines: true)
    }

    /// Which exercises `stored` scopes the feed to, or `nil` for every one of them (`FR-16.3.1`).
    ///
    /// **One home for the resolution, because two screens ask it.** The feed narrows itself by this
    /// and the configuration screen lists the schemes available under it; a second copy is how the
    /// two start disagreeing about what "the dashboard lifts" means for a lifter who has chosen
    /// none.
    ///
    /// **`nonisolated(nonsending)`, so `dashboardDefault` runs on the caller's actor.** Both callers
    /// are `@MainActor` states whose closure reads the catalogue through a stored, non-`Sendable`
    /// resolver; a plain `nonisolated` function would send that closure across an isolation boundary
    /// and the compiler is right to refuse it. Nothing here needs to leave the caller's actor — the
    /// work is a switch over four fields.
    ///
    /// - Parameters:
    ///   - stored: The settings row.
    ///   - dashboardDefault: `FR-1.9.1`'s selection for a lifter who has made none. Run only where
    ///     it is needed — a configured dashboard carries its identifiers on the row.
    /// - Returns: The exercises, or `nil`.
    public nonisolated(nonsending) static func scope(
        of stored: UserSettings,
        dashboardDefault: () async throws -> [UUID]
    ) async rethrows -> Set<UUID>? {
        switch stored.recentRecordsScope {
        case .everyExercise:
            return nil
        case .chosen:
            return Set(stored.recentRecordsExerciseIDs ?? [])
        case .dashboardLifts:
            if let tiled = stored.dashboardExerciseIDs { return Set(tiled) }
            return Set(try await dashboardDefault())
        }
    }

    /// Whether `record` survives the scheme rule and the baseline rule.
    ///
    /// **Everything this type decides, it decides from the entry alone**, which is `NFR-17.2` in
    /// one sentence: `FR-17.3.1` withdrew the threshold, so no case here asks what an exercise's
    /// history holds and the feed reads the record cache and nothing else. The exercise rule is the
    /// one part applied elsewhere — to the cached rows, before they are grouped.
    ///
    /// - Parameter record: The feed entry.
    /// - Returns: Whether it is drawn.
    func admits(_ record: RecentRecord) -> Bool {
        guard showsBaselines || !record.isBaseline else { return false }
        guard case .chosen(let chosen) = schemes else { return true }
        return chosen.contains(record.scheme)
    }
}
