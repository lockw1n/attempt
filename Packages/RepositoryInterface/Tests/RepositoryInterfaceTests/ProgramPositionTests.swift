import Foundation
import PowerliftingCore
import Testing

@testable import RepositoryInterface

/// `FR-16.8.3`: the two columns read back as a position a screen can print.
@Suite("A session's place in a program")
struct ProgramPositionTests {
    /// One home for the conversion, and this is the assertion that pins it: a cursor counts days
    /// from zero and a lifter counts them from one.
    @Test("The day is counted from one and the week is not renumbered")
    func theDayIsCountedFromOne() {
        #expect(session(week: 2, day: 0).programPosition == ProgramPosition(week: 2, day: 1))
        #expect(session(week: 5, day: 3).programPosition == ProgramPosition(week: 5, day: 4))
        // Anchored to a literal on one side: `nil == nil` would satisfy a comparison of two reads.
        #expect(session(week: 2, day: 0).programPosition?.day == 1)
    }

    /// Both columns or neither: a row carrying one describes a position nothing can be drawn from.
    @Test(
        "A half-filled row has no position at all",
        arguments: [(2, nil), (nil, 0), (nil, nil)] as [(Int?, Int?)])
    func aHalfFilledRowHasNoPosition(week: Int?, day: Int?) {
        #expect(session(week: week, day: day).programPosition == nil)
    }

    /// A session with `weekNumber` and `dayIndex` at `week`/`day`, every other column fixed.
    private func session(week: Int?, day: Int?) -> WorkoutSession {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        return WorkoutSession(
            id: UUID(),
            createdAt: moment,
            updatedAt: moment,
            deletedAt: nil,
            date: moment,
            startedAt: moment,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: week == nil && day == nil ? nil : UUID(),
            scheduledWorkoutID: nil,
            weekNumber: week,
            dayIndex: day
        )
    }
}
