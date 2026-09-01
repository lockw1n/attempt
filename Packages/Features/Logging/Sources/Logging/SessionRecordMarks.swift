import Foundation

/// Which sets in the workout hold a personal record, and at which rep counts (`FR-1.6.3`).
///
/// **Keyed on the set, not on the entry or the exercise**, because that is what a badge is drawn
/// against: `PersonalRecordCacheEntity.sourceSetID` names the set holding each N-rep max, so a set is
/// a record exactly when its identifier appears here.
///
/// **One set can hold several.** A five-rep set that is the heaviest at every N up to five holds the
/// 1RM through the 5RM, so the value is a list rather than a flag — and VoiceOver says which,
/// because "personal record" alone does not tell a lifter what they just beat.
///
/// **A set in an earlier session is marked too, and that is the requirement rather than a widening
/// of it.** `FR-1.6.3` asks for the badge at the moment a set is logged; a mark that appeared only on
/// the newest record would have to be untrue about every other record-holding set on the same card,
/// which is a card that says the older sets are not records.
struct SessionRecordMarks: Equatable, Sendable {
    /// The rep counts each record-holding set stands at, ascending. A set that holds none is absent.
    var bySetID: [UUID: [Int]] = [:]

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
    /// - Returns: The rep counts it holds the record at, ascending, or none.
    func repCounts(forSetID setID: UUID) -> [Int] {
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
    /// Which of `exercises`' sets hold a record, and at which rep counts (`FR-1.6.3`).
    ///
    /// **One cache read per distinct exercise, not per card and not per set.** A workout names a
    /// handful of exercises and two entries can name the same one; the read is `G-1.5`'s cached
    /// answer, so a workout of six exercises costs six table reads and no walk of anything.
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
            guard let repMaxes = try? await records.repMaxes(forExerciseID: exerciseID) else {
                continue
            }
            for repMax in repMaxes {
                marks.bySetID[repMax.record.sourceSetID, default: []].append(repMax.reps)
            }
        }
        for setID in marks.bySetID.keys { marks.bySetID[setID]?.sort() }
        marks.hasLoaded = true
        return marks
    }
}
