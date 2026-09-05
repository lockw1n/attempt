import Foundation
import PowerliftingCore
import RepositoryInterface

/// Which exercises the dashboard tiles an estimated max for before the user has chosen
/// (`FR-1.9.1`).
///
/// **Derived from the catalogue rather than from three stored identifiers**, which is the one
/// decision here worth stating. `FR-1.9.1` names *movements* — squat, bench, deadlift — and the
/// catalogue is where the rows answering to them live; writing the seed's three UUIDs into this
/// module would put a copy of a fact whose home is the seed catalogue somewhere it could silently
/// stop matching. It also degrades the right way: a lifter who deleted the barbell bench press
/// simply gets no bench tile, instead of one naming a row that is not there.
///
/// **Nothing is persisted by defaulting.** The stored selection stays `nil` until the user opens the
/// picker, so a catalogue that gains a competition lift later is tiled without a migration — and
/// "never chosen" stays distinguishable from "chose none".
enum DashboardDefaults {
    /// `FR-1.9.1`'s three lifts, in the order the requirement writes them, which is also the order
    /// the tiles are drawn in.
    static let movements: [Movement] = [.squat, .bench, .deadlift]

    /// `FR-1.9.1`'s three lifts as `FR-16.5.1` picks them: the seeded competition lift where the
    /// lifter has been doing it, and the exercise they have actually been doing where they have not.
    ///
    /// **One candidate per movement, chosen by four clauses and a name.** A movement has many rows —
    /// the leg press is a squat and the hip thrust a deadlift — so the competition lift is the one
    /// that is a root exercise (`FR-1.1.7`'s variations belong under it), performed with a barbell,
    /// from the seed rather than the user's own, and not archived. The shipped catalogue leaves that
    /// unambiguous for squat and bench and offers three deadlifts; the name settles it, and the
    /// alphabetical rule is a tiebreak rather than a claim — any of the three would be defensible,
    /// and what matters is that the same lifter gets the same tile on every launch.
    ///
    /// **The name that settles it is the English one, and it is not a display decision**
    /// (`FR-1.14.2` is about what a screen shows). This picks *which* exercise gets a tile on a
    /// dashboard nobody has configured; resolving it per locale would hand a lifter a different
    /// deadlift for switching their phone's language, and the tiles they see are named in their own
    /// language either way.
    ///
    /// **A default with no history is replaced, and the replacement is filtered by nothing**
    /// (`FR-16.5.1`). The four clauses above say which row *is* the squat; they have no business
    /// deciding what a lifter who does not squat should be shown instead, which is simply whatever
    /// they train most. A lifter logging dumbbell work and chin-ups gets dumbbell work and chin-ups,
    /// not two empty blocks headed by lifts they have never performed.
    ///
    /// **A slot with no replacement available keeps its own lift**, which is what a store with
    /// nothing in it draws: three named tiles with no numbers yet, rather than no tiles at all. The
    /// competition lifts are the right guess for a lifter who has not told the app anything.
    ///
    /// **Nothing is chosen twice.** The kept lifts are reserved before the gaps are filled, so a
    /// bench press that is both the second movement's own candidate and the most-trained exercise in
    /// the log is tiled once, in its own slot.
    ///
    /// - Parameters:
    ///   - catalogue: The exercises to choose from.
    ///   - mostTrained: Every exercise with a completed working set in the lookback window,
    ///     most-trained first — ``DerivedValues/PersonalRecordRecomputer/mostTrainedExerciseIDs()``.
    ///     Membership is what "has history" means here, and the order is what replaces a lift that
    ///     has none.
    /// - Returns: One identifier per movement that had a candidate, in ``movements``' order.
    static func exerciseIDs(in catalogue: [Exercise], mostTrained: [UUID]) -> [UUID] {
        let candidates = movements.map { seededLift(for: $0, in: catalogue) }
        let trained = Set(mostTrained)
        let kept = candidates.map { candidate -> UUID? in
            guard let candidate, trained.contains(candidate) else { return nil }
            return candidate
        }
        let reserved = Set(kept.compactMap { $0 })
        let tileable = Set(catalogue.filter { !$0.isArchived }.map(\.id))
        var replacements = mostTrained.filter {
            !reserved.contains($0) && tileable.contains($0)
        }[...]
        return zip(kept, candidates).compactMap { keptLift, candidate in
            if let keptLift { return keptLift }
            return replacements.popFirst() ?? candidate
        }
    }

    /// Today's selection for a caller with no training history in hand — the seeded three, whether
    /// or not they have ever been performed.
    ///
    /// - Parameter catalogue: The exercises to choose from.
    /// - Returns: One identifier per movement that had a candidate, in ``movements``' order.
    static func exerciseIDs(in catalogue: [Exercise]) -> [UUID] {
        exerciseIDs(in: catalogue, mostTrained: [])
    }

    /// The competition lift for one movement, by the four clauses and the name.
    private static func seededLift(for movement: Movement, in catalogue: [Exercise]) -> UUID? {
        catalogue
            .filter {
                $0.movement == movement && $0.parentExerciseID == nil
                    && $0.equipment == .barbell && !$0.isCustom && !$0.isArchived
            }
            .min { $0.name < $1.name }?
            .id
    }
}
