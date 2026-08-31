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

    /// The exercise each of ``movements`` resolves to, for the ones the catalogue can answer.
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
    /// - Parameter catalogue: The exercises to choose from.
    /// - Returns: One identifier per movement that had a candidate, in ``movements``' order.
    static func exerciseIDs(in catalogue: [Exercise]) -> [UUID] {
        movements.compactMap { movement in
            catalogue
                .filter {
                    $0.movement == movement && $0.parentExerciseID == nil
                        && $0.equipment == .barbell && !$0.isCustom && !$0.isArchived
                }
                .min { $0.name < $1.name }?
                .id
        }
    }
}
