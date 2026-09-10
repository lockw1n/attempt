import DerivedValues
import DesignSystem
import Foundation
import PowerliftingCore
import SwiftUI

/// Which sets in the workout hold a personal record, and at which schemes (`FR-1.6.3`,
/// `FR-16.2.4`).
///
/// **Keyed on the set, not on the entry or the exercise**, because that is what a badge is drawn
/// against: `PersonalRecordCacheEntity.sourceSetID` names the **first set of the run** holding each
/// cell, so a set is a record exactly when its identifier appears here — and the set that carries
/// the badge for a run of four is the one the run starts at.
///
/// **The value is a list, and since `FR-17.2.1` it is never more than one long.** A run holds one
/// cell and a run is named by its first set, so a set holds one cell or none; the list stays because
/// nothing in the store enforces that — a cache another build wrote, restored from a backup, can
/// still name one set several times — and what the badge names is the maximal one (`FR-16.2.4`).
///
/// **A set in an earlier session is marked too, and that is the requirement rather than a widening
/// of it.** `FR-1.6.3` asks for the badge at the moment a set is logged; a mark that appeared only on
/// the newest record would have to be untrue about every other record-holding set on the same card,
/// which is a card that says the older sets are not records.
struct SessionRecordMarks: Equatable, Sendable {
    /// The cells each record-holding set stands at. A set that holds none is absent.
    var bySetID: [UUID: [SchemeMark]] = [:]

    /// Whether anything has looked yet.
    ///
    /// A set holding no record and one nothing has looked up are both a miss in the dictionary, and
    /// the badge would be equally absent for both — this is what stops a card drawn before the first
    /// look from being read as a workout with no records in it. See ``PreviousPerformances/hasLoaded``
    /// for the same distinction on the same screen.
    var hasLoaded = false

    /// What one row's badge reports.
    ///
    /// - Parameter setID: The set the row draws.
    /// - Returns: The cells it stands at, or none.
    func marks(forSetID setID: UUID) -> [SchemeMark] {
        guard hasLoaded else { return [] }
        return bySetID[setID] ?? []
    }
}

/// One cell a set stands at, and which of `FR-17.2.2`'s two *performed* states it is in.
///
/// **The third state is not here.** Never-performed is a property of a cell nobody reached, so it
/// exists on the records table and cannot exist on a set: a set that was logged performed its own
/// scheme. See ``ExerciseLibrary/ExerciseSchemeTable``, where all three are answered.
///
/// **A pair rather than a `RecordScheme` alone, because the badge and the feed have to agree**
/// (`FR-16.3.4`, finding 02). The feed hides a first performance by default; a badge saying **PR**
/// over one would be the two surfaces contradicting each other on the same run.
/// **Public where ``SessionRecordMarks`` is internal**, because ``DayRow`` carries a list of these
/// across the module boundary and the marks themselves do not travel.
public struct SchemeMark: Equatable, Sendable {
    /// The cell.
    public let scheme: RecordScheme

    /// Whether that cell had never been performed for this exercise before — `FR-16.2.3`'s baseline.
    public let isFirstPerformance: Bool

    /// Creates a mark.
    ///
    /// - Parameters:
    ///   - scheme: The cell.
    ///   - isFirstPerformance: Whether it is `FR-16.2.3`'s baseline.
    public init(scheme: RecordScheme, isFirstPerformance: Bool) {
        self.scheme = scheme
        self.isFirstPerformance = isFirstPerformance
    }
}

/// Where the marks come from.
///
/// **A reader beside the type rather than a member of a store**, and that is what lets three
/// surfaces share one: the workout in progress, a past session and a day's checklist all draw the
/// same badge over the same cache, and a read that lived on ``ActiveSessionStore`` would be
/// unreachable from a screen that holds no workout.
extension SessionRecordMarks {
    /// Which of `exercises`' sets hold a record, and at which schemes (`FR-1.6.3`, `FR-16.2.4`).
    ///
    /// **The cache's truth, which is *holds the record now* and not *set a record then*.** The
    /// table is rebuilt from the log, so a run since beaten carries nothing (`FR-17.7.2`) — a badge
    /// asserting a record the lifter no longer holds is worse on a screen about last month than it
    /// would be on today's. This is the read a past day makes too, and it is why both screens say
    /// the same thing about the same set.
    ///
    /// **One cache read per distinct exercise, not per card and not per set.** A workout names a
    /// handful of exercises and two entries can name the same one; the read is `G-1.5`'s cached
    /// answer, so a workout of six exercises costs six table reads and no walk of anything.
    ///
    /// **The whole table, not `FR-1.6.1`'s one-set column.** `FR-16.2.4` asks the badge to name the
    /// scheme the group set, and since `FR-17.2.1` a run of five sets stands *only* at five sets —
    /// read through the one-set column every group of two or more would carry no badge at all.
    ///
    /// **A refusal costs that exercise its badges and nothing else.** The sets are stored and drawn
    /// either way, and a derived value that could not be read is not something to fail a workout
    /// over (`G-1.4`) — the same swallow the recompute triggers make, for the same reason.
    ///
    /// - Parameters:
    ///   - exercises: The workout's exercises, already read.
    ///   - records: The app's one recompute actor, which owns the cache (`TR-1.6`).
    /// - Returns: The marks, ready to hand to the rows.
    static func read(
        over exercises: [SessionExercise], from records: PersonalRecordRecomputer
    ) async -> SessionRecordMarks {
        var marks = SessionRecordMarks()
        for exerciseID in Set(exercises.map(\.entry.exerciseID)) {
            guard let cells = try? await records.schemeRecords(forExerciseID: exerciseID) else {
                continue
            }
            for cell in cells {
                marks.bySetID[cell.record.sourceSetID, default: []]
                    .append(SchemeMark(scheme: cell.scheme, isFirstPerformance: cell.previous == nil))
            }
        }
        for setID in marks.bySetID.keys {
            marks.bySetID[setID]?.sort { $0.scheme < $1.scheme }
        }
        marks.hasLoaded = true
        return marks
    }
}

/// What one badge says (`FR-1.6.3`, `FR-16.2.4`).
///
/// **A value rather than two branches inside a view body**, so which of the two spellings a set or a
/// run gets is a claim a test can hold — `SetRow` and `SetGroupRow` draw the same badge over
/// different collections of cells, and a rule written twice inside two `body`s can only be closed by
/// a picture.
struct RecordBadge: Equatable {
    /// The maximal scheme among the cells the badge covers — see ``PowerliftingCore/RecordScheme/maximal(of:)``.
    let scheme: RecordScheme

    /// Whether that cell is a first performance rather than a beaten load (`FR-17.2.2`).
    let isFirstPerformance: Bool

    /// The badge over `marks`, or `nil` where there are none and no badge is drawn.
    ///
    /// - Parameter marks: Every cell the set or run stands at.
    init?(marks: some Sequence<SchemeMark>) {
        let all = Array(marks)
        guard let maximal = RecordScheme.maximal(of: all.lazy.map(\.scheme)),
            let mark = all.first(where: { $0.scheme == maximal })
        else { return nil }
        scheme = maximal
        isFirstPerformance = mark.isFirstPerformance
    }

    /// What the row draws — `PR · 5×5`, or `First · 5×5` (`FR-17.2.3`, `Q-17.1`).
    var text: LocalizedStringResource {
        switch (isFirstPerformance, scheme.sets == 1) {
        case (false, true): LoggingStrings.setPersonalRecordReps(scheme.reps)
        case (false, false): LoggingStrings.setPersonalRecordScheme(reps: scheme.reps, sets: scheme.sets)
        case (true, true): LoggingStrings.setFirstPerformanceReps(scheme.reps)
        case (true, false): LoggingStrings.setFirstPerformanceScheme(reps: scheme.reps, sets: scheme.sets)
        }
    }

    /// What VoiceOver reads instead (`G-4.2`).
    var label: LocalizedStringResource {
        switch (isFirstPerformance, scheme.sets == 1) {
        case (false, true): LoggingStrings.setPersonalRecordRepsLabel(scheme.reps)
        case (false, false):
            LoggingStrings.setPersonalRecordSchemeLabel(reps: scheme.reps, sets: scheme.sets)
        case (true, true): LoggingStrings.setFirstPerformanceRepsLabel(scheme.reps)
        case (true, false):
            LoggingStrings.setFirstPerformanceSchemeLabel(reps: scheme.reps, sets: scheme.sets)
        }
    }
}

/// The badge itself, wherever a row draws one (`FR-1.6.3`, `FR-17.2.2`).
///
/// **One view rather than the three identical bodies it replaces.** ``SetRow``, ``SetGroupRow``
/// and ``DayExerciseRow`` each drew the capsule by hand, so `FR-17.2.2`'s second state would have
/// been three edits and three chances to draw it differently — T-16.17's rule about a decision that
/// lives in more than one `body`.
///
/// **The two states differ by their word and by their weight, never by tint alone** (`G-4.5`). A
/// record is the filled accent it has always been; a first performance is an outlined capsule in
/// secondary text, which reads as quieter in a monochrome rendering too — and the words *PR* and
/// *First* carry the distinction on their own.
struct RecordBadgeView: View {
    /// What the badge says.
    let badge: RecordBadge

    /// The capsule.
    var body: some View {
        Text(badge.text)
            .font(Typography.metricLabel.font)
            .foregroundStyle(
                badge.isFirstPerformance ? ColorToken.textSecondary : ColorToken.onBrandAccent
            )
            .padding(.horizontal, Spacing.sm.points)
            .padding(.vertical, Spacing.xxs.points)
            .background {
                if badge.isFirstPerformance {
                    Capsule().strokeBorder(ColorToken.separator, lineWidth: 1)
                } else {
                    Capsule().fill(ColorToken.brandAccent)
                }
            }
            .accessibilityLabel(Text(badge.label))
    }
}
