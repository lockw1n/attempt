import Foundation
import PowerliftingCore

/// Which sets in the workout hold a personal record, and at which schemes (`FR-1.6.3`,
/// `FR-16.2.4`).
///
/// **Keyed on the set, not on the entry or the exercise**, because that is what a badge is drawn
/// against: `PersonalRecordCacheEntity.sourceSetID` names the **first set of the run** holding each
/// cell, so a set is a record exactly when its identifier appears here — and the set that carries
/// the badge for a run of four is the one the run starts at.
///
/// **One set can hold several.** A five-rep set that is the heaviest at every N up to five holds the
/// 1RM through the 5RM, and a run of four holds up to forty cells — so the value is a list rather
/// than a flag, and what the badge names is the maximal one (`FR-16.2.4`).
///
/// **A set in an earlier session is marked too, and that is the requirement rather than a widening
/// of it.** `FR-1.6.3` asks for the badge at the moment a set is logged; a mark that appeared only on
/// the newest record would have to be untrue about every other record-holding set on the same card,
/// which is a card that says the older sets are not records.
struct SessionRecordMarks: Equatable, Sendable {
    /// The schemes each record-holding set stands at. A set that holds none is absent.
    var bySetID: [UUID: [RecordScheme]] = [:]

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
    /// - Returns: The schemes it holds the record at, or none.
    func schemes(forSetID setID: UUID) -> [RecordScheme] {
        guard hasLoaded else { return [] }
        return bySetID[setID] ?? []
    }
}

/// Where the marks come from.
///
/// **Beside the type rather than on the store**, which is also what keeps
/// `ActiveSessionStore.swift` under SwiftLint's file ceiling: this reads the cache and writes
/// nothing, so unlike every other member of that store it does not need the file scope its
/// `private(set)` properties are protected by.
extension ActiveSessionStore {
    /// Which of `exercises`' sets hold a record, and at which schemes (`FR-1.6.3`, `FR-16.2.4`).
    ///
    /// **One cache read per distinct exercise, not per card and not per set.** A workout names a
    /// handful of exercises and two entries can name the same one; the read is `G-1.5`'s cached
    /// answer, so a workout of six exercises costs six table reads and no walk of anything.
    ///
    /// **The whole table, not `FR-1.6.1`'s one-set column.** `FR-16.2.4` asks the badge to name the
    /// maximal scheme the group set, and a run whose records all stand at two sets and up sets no
    /// rep max at all — read through the column it would carry no badge, which is the gap
    /// ``SetGroupRow/recordMark`` documented until this read closed it.
    ///
    /// **A refusal costs that exercise its badges and nothing else.** The sets are stored and drawn
    /// either way, and a derived value that could not be read is not something to fail a workout
    /// over (`G-1.4`) — the same swallow the recompute triggers make, for the same reason.
    ///
    /// - Parameter exercises: The workout's exercises, already read.
    /// - Returns: The marks, ready to hand to the cards.
    func recordMarks(over exercises: [SessionExercise]) async -> SessionRecordMarks {
        var marks = SessionRecordMarks()
        for exerciseID in Set(exercises.map(\.entry.exerciseID)) {
            guard let cells = try? await records.schemeRecords(forExerciseID: exerciseID) else {
                continue
            }
            for cell in cells {
                marks.bySetID[cell.record.sourceSetID, default: []].append(cell.scheme)
            }
        }
        for setID in marks.bySetID.keys { marks.bySetID[setID]?.sort() }
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

    /// The badge over `schemes`, or `nil` where there are none and no badge is drawn.
    ///
    /// - Parameter schemes: Every cell the set or run holds a record at.
    init?(schemes: some Sequence<RecordScheme>) {
        guard let maximal = RecordScheme.maximal(of: schemes) else { return nil }
        scheme = maximal
    }

    /// What the row draws.
    var text: LocalizedStringResource {
        scheme.sets == 1
            ? LoggingStrings.setPersonalRecordRepMax(scheme.reps)
            : LoggingStrings.setPersonalRecordScheme(reps: scheme.reps, sets: scheme.sets)
    }

    /// What VoiceOver reads instead (`G-4.2`).
    var label: LocalizedStringResource {
        scheme.sets == 1
            ? LoggingStrings.setPersonalRecordRepMaxLabel(scheme.reps)
            : LoggingStrings.setPersonalRecordSchemeLabel(reps: scheme.reps, sets: scheme.sets)
    }
}
