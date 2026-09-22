import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// FR-18.8.3, DOD-18.12. What a *filtered* list read answers when the two rows of an id disagree
// about the column the filter reads.
//
// `DuplicateIDListReadTests` pins that a list read answers one row per id. Every pair there agrees
// about the filtered column, so none of those fixtures can hold this defect: the predicate drops
// the winner before the rule sees the pair, and the stale twin — the only row that matched — is
// answered as if it were the record. Here every pair disagrees about exactly that column, and the
// expectation is anchored to which twin came back, never to a count.
//
// The four sites whose filtered column a lifter can move are each read once: a run's `endedAt`
// (`startRun(_:)` closes the others), a session's `date` (`PastSessionState.changeDate(to:)`), a
// bodyweight entry's `date`, and a profile's `isDefault` (`makeDefault(profileID:)`). The rule is
// one function, so one of these failing means all of them do; each is still read at its own site
// so a site moved to `allRows`, or resolved before it filters, fails its own test.
//
// The last test crosses the id-group boundary the second fetch is sent in: past that many matched
// ids the read makes more than one lookup, and a pair straddling two groups must still be one pair.

@Suite("A filtered read answers with the winner, or with nothing")
struct FilteredReadResolvesFirstTests {
    // MARK: - currentRun(): endedAt == nil, in the four clause shapes

    @Test("A run held twice, the later-stamped row ended, is not current (DOD-18.12)")
    func endedWinnerIsNotCurrent() async throws {
        let harness = try RepositoryHarness()
        let program = UUID()
        let id = UUID()
        try harness.seed([
            twin(programRecord(id: program), as: ProgramEntity.self, updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, endedAt: nil, weekNumber: 3),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, endedAt: fixtureUpdatedAt, weekNumber: 4),
                as: ProgramRunEntity.self,
                updatedAt: twinNewer),
        ])

        #expect(try await harness.stack.programs.currentRun() == nil)
    }

    @Test("Beside an ended pair, the run that is genuinely open is the current one")
    func endedWinnerYieldsToTheOpenRun() async throws {
        let harness = try RepositoryHarness()
        let program = UUID()
        let id = UUID()
        let open = UUID()
        // The stale twin starts *after* the open run, so if it were answered it would outrank the
        // open run on `currentRun()`'s key rather than tie with it and fall to the uuid.
        let staleStart = fixtureCreatedAt - 86_400
        try harness.seed([
            twin(programRecord(id: program), as: ProgramEntity.self, updatedAt: twinOlder),
            twin(
                programRunRecord(
                    id: id, programID: program, startedAt: staleStart, endedAt: nil, weekNumber: 3),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, endedAt: fixtureUpdatedAt, weekNumber: 4),
                as: ProgramRunEntity.self,
                updatedAt: twinNewer),
            twin(
                programRunRecord(id: open, programID: program, endedAt: nil, weekNumber: 7),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
        ])

        let current = try await harness.stack.programs.currentRun()
        #expect(current?.id == open)
        #expect(current?.weekNumber == 7)
    }

    @Test("The winner open and the loser ended: the winner is current, with its own contents")
    func openWinnerIsCurrent() async throws {
        let harness = try RepositoryHarness()
        let program = UUID()
        let id = UUID()
        try harness.seed([
            twin(programRecord(id: program), as: ProgramEntity.self, updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, endedAt: fixtureUpdatedAt, weekNumber: 3),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, endedAt: nil, weekNumber: 4),
                as: ProgramRunEntity.self,
                updatedAt: twinNewer),
        ])

        #expect(try await harness.stack.programs.currentRun()?.weekNumber == 4)
    }

    @Test("Both open: the winner is current, with its own contents")
    func bothOpenAnswersTheWinner() async throws {
        let harness = try RepositoryHarness()
        let program = UUID()
        let id = UUID()
        try harness.seed([
            twin(programRecord(id: program), as: ProgramEntity.self, updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, endedAt: nil, weekNumber: 3),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, endedAt: nil, weekNumber: 4),
                as: ProgramRunEntity.self,
                updatedAt: twinNewer),
        ])

        #expect(try await harness.stack.programs.currentRun()?.weekNumber == 4)
    }

    @Test("Both ended: nothing is current")
    func bothEndedAnswersNothing() async throws {
        let harness = try RepositoryHarness()
        let program = UUID()
        let id = UUID()
        try harness.seed([
            twin(programRecord(id: program), as: ProgramEntity.self, updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, endedAt: fixtureCreatedAt, weekNumber: 3),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, endedAt: fixtureUpdatedAt, weekNumber: 4),
                as: ProgramRunEntity.self,
                updatedAt: twinNewer),
        ])

        #expect(try await harness.stack.programs.currentRun() == nil)
    }

    // MARK: - sessions(in:): a session's date

    @Test("A session re-dated out of a range is not in that range, and is in the new one once")
    func reDatedSessionDrawsUnderItsNewDateOnly() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = oldDate + 10 * 86_400
        try harness.seed([
            twin(
                sessionRecord(id: id, date: oldDate, notes: "where it was"),
                as: WorkoutSessionEntity.self,
                updatedAt: twinOlder),
            twin(
                sessionRecord(id: id, date: newDate, notes: "where it moved to"),
                as: WorkoutSessionEntity.self,
                updatedAt: twinNewer),
        ])

        let oldRange = (oldDate - 86_400)...(oldDate + 86_400)
        let newRange = (newDate - 86_400)...(newDate + 86_400)
        let underOldDate = try await harness.stack.workouts.sessions(
            in: oldRange, includingDeleted: false)
        let underNewDate = try await harness.stack.workouts.sessions(
            in: newRange, includingDeleted: false)
        #expect(underOldDate.map(\.notes) == [])
        #expect(underNewDate.map(\.notes) == ["where it moved to"])
    }

    @Test("A winner that is soft-deleted still hides the record (FR-18.8.2)")
    func deletedWinnerHidesTheRecord() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let deleted = twin(
            sessionRecord(id: id, date: date, notes: "deleted winner"),
            as: WorkoutSessionEntity.self,
            updatedAt: twinNewer)
        deleted.deletedAt = twinNewer
        try harness.seed([
            twin(
                sessionRecord(id: id, date: date - 3_600, notes: "live loser"),
                as: WorkoutSessionEntity.self,
                updatedAt: twinOlder),
            deleted,
        ])

        let range = (date - 86_400)...(date + 86_400)
        let live = try await harness.stack.workouts.sessions(in: range, includingDeleted: false)
        let all = try await harness.stack.workouts.sessions(in: range, includingDeleted: true)
        #expect(live.map(\.notes) == [])
        #expect(all.map(\.notes) == ["deleted winner"])
    }

    // MARK: - bodyweight entries(in:): an entry's date

    @Test("A bodyweight reading re-dated out of a range is answered under its new date only")
    func reDatedBodyweightDrawsUnderItsNewDateOnly() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = oldDate + 10 * 86_400
        try harness.seed([
            twin(
                bodyweightRecord(id: id, date: oldDate, grams: 80_000),
                as: BodyweightEntryEntity.self,
                updatedAt: twinOlder),
            twin(
                bodyweightRecord(id: id, date: newDate, grams: 81_000),
                as: BodyweightEntryEntity.self,
                updatedAt: twinNewer),
        ])

        let underOldDate = try await harness.stack.bodyweight.entries(
            in: (oldDate - 86_400)...(oldDate + 86_400), includingDeleted: false)
        let underNewDate = try await harness.stack.bodyweight.entries(
            in: (newDate - 86_400)...(newDate + 86_400), includingDeleted: false)
        #expect(underOldDate.map(\.weight.grams) == [])
        #expect(underNewDate.map(\.weight.grams) == [81_000])
    }

    // MARK: - defaultProfile(): isDefault

    @Test("A profile whose later-stamped row dropped the flag is not the default")
    func unflaggedWinnerIsNotDefault() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(
                profileRecord(id: id, name: "was default", isDefault: true),
                as: EquipmentProfileEntity.self,
                updatedAt: twinOlder),
            twin(
                profileRecord(id: id, name: "no longer", isDefault: false),
                as: EquipmentProfileEntity.self,
                updatedAt: twinNewer),
        ])

        #expect(try await harness.stack.equipment.defaultProfile() == nil)
    }

    @Test("Beside such a pair, the profile that genuinely carries the flag is the default")
    func unflaggedWinnerYieldsToTheFlaggedProfile() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(
                profileRecord(id: id, name: "was default", isDefault: true),
                as: EquipmentProfileEntity.self,
                updatedAt: twinOlder),
            twin(
                profileRecord(id: id, name: "no longer", isDefault: false),
                as: EquipmentProfileEntity.self,
                updatedAt: twinNewer),
            twin(
                profileRecord(name: "Gym", isDefault: true),
                as: EquipmentProfileEntity.self,
                updatedAt: twinOlder),
        ])

        #expect(try await harness.stack.equipment.defaultProfile()?.name == "Gym")
    }

    // MARK: - The second fetch is sent in groups

    @Test("Past one id group, a pair in the second group is still one pair, and still re-checked")
    func pairsAcrossIDGroupsResolve() async throws {
        let harness = try RepositoryHarness()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let range = (date - 86_400)...(date + 86_400)
        var rows: [any PersistentModel] = []
        for _ in 0..<idFetchGroup {
            rows.append(
                twin(
                    sessionRecord(date: date, notes: "single"),
                    as: WorkoutSessionEntity.self,
                    updatedAt: twinOlder))
        }
        let stillInRange = UUID()
        let movedOut = UUID()
        rows += [
            twin(
                sessionRecord(id: stillInRange, date: date, notes: "older twin"),
                as: WorkoutSessionEntity.self,
                updatedAt: twinOlder),
            twin(
                sessionRecord(id: stillInRange, date: date, notes: "newer twin"),
                as: WorkoutSessionEntity.self,
                updatedAt: twinNewer),
            twin(
                sessionRecord(id: movedOut, date: date, notes: "older, in range"),
                as: WorkoutSessionEntity.self,
                updatedAt: twinOlder),
            twin(
                sessionRecord(id: movedOut, date: date + 10 * 86_400, notes: "newer, moved out"),
                as: WorkoutSessionEntity.self,
                updatedAt: twinNewer),
        ]
        try harness.seed(rows)

        let read = try await harness.stack.workouts.sessions(in: range, includingDeleted: false)
        #expect(read.count == idFetchGroup + 1)
        #expect(read.filter { $0.notes != "single" }.map(\.notes) == ["newer twin"])
    }
}
