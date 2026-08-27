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
