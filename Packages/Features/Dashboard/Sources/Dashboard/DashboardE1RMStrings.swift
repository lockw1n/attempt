import DerivedValues
import Foundation
import PowerliftingCore

/// `FR-1.9.1`'s copy: the tiles, their delta, the picker, and the seven reasons a tile has no number.
///
/// A file of its own rather than more of ``DashboardStrings``, on `ExerciseLibraryE1RMStrings`'
/// rule — same type, same catalogue, same key convention.
extension DashboardStrings {
    /// The tiles' heading.
    static let tilesTitle = resource("dashboard.tiles.title")

    /// The tiles could not be read — a retry may fix it.
    static let tilesError = resource("dashboard.tiles.error")

    /// Nothing is tiled: the user removed every tile, or every one they chose names an exercise the
    /// catalogue no longer holds.
    static let tilesNoneChosen = resource("dashboard.tiles.none.headline")

    /// What to do about it. The control itself is the link directly beneath.
    static let tilesNoneChosenMessage = resource("dashboard.tiles.none.message")

    /// `FR-1.7.5`'s "clearly marked as manual", in the context line a delta would otherwise hold.
    static let tileManual = resource("dashboard.tiles.manual")

    /// There is a number but nothing earlier to compare it with — a first estimate, or the only one
    /// inside the window.
    static let tileNoPrevious = resource("dashboard.tiles.no-previous")

    /// The control that opens the picker.
    static let tilesChooseAction = resource("dashboard.tiles.choose.action")

    /// The picker's own title.
    static let tilesChooseTitle = resource("dashboard.tiles.choose.title")

    /// The catalogue holds nothing that could be tiled.
    static let tilesChooseEmpty = resource("dashboard.tiles.choose.empty")

    /// The catalogue could not be read.
    static let tilesChooseError = resource("dashboard.tiles.choose.error")

    /// A tile could not be added or removed. Nothing changed.
    static let tilesChooseWriteError = resource("dashboard.tiles.choose.write-error")

    /// Why a tiled exercise shows no number (`FR-1.13.3`).
    ///
    /// **The same seven sentences the exercise detail screen shows, deliberately.** The refusal is
    /// the calculator's and is carried up as data, so the two screens explaining it differently
    /// would be two accounts of one fact — see `ExerciseLibraryStrings.e1rmAbsence(_:days:)`, whose
    /// wording this matches, and the three rules that travel with it: only `.noSetsLogged` may say
    /// "log a set", the reason is the *nearest miss* among in-window sets, and it is drawn from
    /// in-window sets alone.
    ///
    /// They are separate catalogue entries rather than one shared string because a package's copy
    /// resolves against that package's own bundle (`G-3.4`); one home for the *decision* is this
    /// file's doc comment pointing at the other, since neither module may import the other.
    ///
    /// - Parameters:
    ///   - absence: Why the estimate is missing.
    ///   - days: The window's length, which every in-window sentence names.
    /// - Returns: The sentence.
    static func tileAbsence(_ absence: EstimateAbsence, days: Int) -> LocalizedStringResource {
        switch absence {
        case .noSetsLogged: resource("dashboard.tiles.absence.none")
        case .noneInWindow: resource("dashboard.tiles.absence.stale \(days)")
        case .refused(.warmup): resource("dashboard.tiles.absence.warmups \(days)")
        case .refused(.incomplete): resource("dashboard.tiles.absence.incomplete \(days)")
        case .refused(.assisted): resource("dashboard.tiles.absence.assisted")
        case .refused(.repsOutOfRange): resource("dashboard.tiles.absence.high-reps \(days)")
        case .refused(.formulaDeclined): resource("dashboard.tiles.absence.no-effort")
        }
    }

    /// Every reason a tile can be numberless, so ``DashboardStrings/all`` covers each sentence.
    static var absences: [EstimateAbsence] {
        [.noSetsLogged, .noneInWindow] + E1RMRefusal.allCases.map(EstimateAbsence.refused)
    }
}
