import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// One row of the session list: what a past workout was, in four facts (`FR-1.5.1`).
///
/// A value type built once per session and never re-read, which is the whole of this screen's
/// answer to `NFR-1.5`: scrolling reads nothing, because a row holds numbers rather than a
/// repository. The session's own records are not carried — a row that held its sets would be the
/// eager per-row load `NFR-1.5` cannot survive.
struct SessionSummary: Identifiable, Equatable, Sendable {
    /// The session this summarises. Also the row's identity and the identifier its route carries.
    let id: UUID

    /// The training day (`FR-1.2.1` backdates, so this is not when it was entered).
    let date: Date

    /// What was trained, in the order the exercises were performed, each named once.
    ///
    /// A repeated exercise — squats, then benches, then back-off squats — appears once: a summary
    /// line reading "Squat, Bench Press and Squat" says nothing the first two did not.
    let exerciseNames: [String]

    /// How many working sets were performed — completed, and not warmups (`G-1.8`).
    let setCount: Int

    /// The load moved, over the sets ``DerivedValues/Tonnage`` can weigh.
    ///
    /// **Not every set in ``setCount`` is in here**, and the difference is a silent omission this
    /// screen does not yet explain: see ``DerivedValues/Tonnage``.
    let tonnage: Weight

    /// The session's own note (`FR-1.2.9`), or empty.
    ///
    /// **This is where a note first becomes readable.** It is written on the workout in progress and
    /// has been stored since schema v1 with nothing showing it; the summary line is the first
    /// surface that does.
    let notes: String

    /// Which week and day of a program the session was started from, or `nil` (`FR-16.8.3`).
    ///
    /// **This is what retires the structure a note used to carry** (`DOD-16.1`): the row above is
    /// where a lifter browsing their log read "W2D1", and it read it out of ``notes`` because
    /// nothing else held it. Defaulted so a row built before a program existed still compiles as
    /// what it is — a session started outside one.
    var programPosition: ProgramPosition?
}
