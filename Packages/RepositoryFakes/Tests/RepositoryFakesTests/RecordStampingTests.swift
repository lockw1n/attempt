import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import RepositoryFakes

/// One record shape with both stamping checks already bound to its concrete type.
///
/// `AuditStamped` returns `Self`, so there is no `[any AuditStamped]` to iterate — the generic call
/// has to be captured at the point the type is known. That is the whole job of this box, and it is
/// what lets the eight shapes be listed **once** instead of once per check: a record added to
/// ``RecordStampingTests/everyRecordShape`` is covered by both, which is precisely what listing
/// them twice failed to do.
private struct StampingCase: Sendable {
    let name: String
    let roundTrips: @Sendable (Date, Date) -> Bool
    let changesTheFour: @Sendable (Date, Date) -> Bool

    init<Record: AuditStamped>(_ name: String, _ record: Record) {
        self.name = name
        roundTrips = { first, second in
            record
                .stamped(createdAt: first, updatedAt: second, deletedAt: second)
                .stamped(
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    deletedAt: record.deletedAt)
                == record
        }
        changesTheFour = { first, second in
            let stamped = record.stamped(createdAt: first, updatedAt: second, deletedAt: second)
            return stamped.createdAt == first && stamped.updatedAt == second
                && stamped.deletedAt == second && stamped.id == record.id
        }
    }
}

/// The fakes' own machinery: twelve hand-written restatements of a memberwise initialiser, one per
/// record type, and a dropped column in any of them is a column a save silently reverts.
///
/// **Two checks, because neither is sufficient alone.** The round trip is a *total* claim about the
/// columns carried through — stamp to new values and back, and require an identical record, which
/// no forgotten `let` survives. It is also blind to the opposite defect: a `stamped` that ignores
/// its parameters makes the round trip a no-op and still compares equal. The second check is what
/// sees that one. Records are `Hashable`, so both comparisons are free.
@Suite("The fakes' audit-column rewriting")
struct RecordStampingTests {
    private static let first = Date(timeIntervalSince1970: 1)
    private static let second = Date(timeIntervalSince1970: 2)

    /// The record types the fakes stamp — **one list, walked by both checks.**
    ///
    /// Eleven of the twelve conformances: ``PersonalRecordCache`` is the one absent, and was
    /// already absent before the three routine shapes were added beside it.
    ///
    /// Listing the shapes per check is what let `UserSettings.stamped` ignore all three of its
    /// arguments with the whole 59-test suite green: the round trip was applied to eight and the
    /// parameter check to three, and the three were the ones somebody happened to think of.
    private static let everyRecordShape: [StampingCase] = {
        let entryID = UUID()
        let exerciseID = UUID()
        return [
            StampingCase(
                "Exercise", exerciseRecord(parentExerciseID: UUID(), isArchived: true)),
            StampingCase(
                "TrainingMaxEntry",
                trainingMaxRecord(exerciseID: exerciseID, effectiveFrom: second)),
            StampingCase("WorkoutSession", sessionRecord(notes: "a note")),
            StampingCase(
                "ExerciseEntry",
                entryRecord(sessionID: UUID(), exerciseID: exerciseID, order: 3)),
            StampingCase(
                "SetEntry",
                setRecord(
                    entryID: entryID,
                    order: 2,
                    isWarmup: true,
                    isCompleted: false,
                    modifiers: [SetModifier(.belt)])),
            StampingCase("BodyweightEntry", bodyweightRecord()),
            StampingCase("EquipmentProfile", profileRecord(isDefault: true)),
            StampingCase("UserSettings", settingsRecord()),
            StampingCase("Routine", routineRecord(name: "Squat day")),
            StampingCase(
                "RoutineExercise",
                routineExerciseRecord(routineID: UUID(), exerciseID: exerciseID, order: 3)),
            StampingCase(
                "RoutineTargetGroup",
                routineTargetGroupRecord(
                    routineExerciseID: UUID(), order: 1, grams: 90_000, reps: 4, sets: 4)),
            StampingCase(
                "PlannedTargetGroup",
                plannedTargetGroupRecord(
                    exerciseEntryID: entryID, order: 1, grams: 90_000, reps: 4, sets: 4)),
        ]
    }()

    @Test("Stamping carries every other column through, on all twelve listed record types")
    func stampingIsLossless() throws {
        #expect(Self.everyRecordShape.count == 12)
        for shape in Self.everyRecordShape {
            #expect(shape.roundTrips(Self.first, Self.second), "\(shape.name)")
        }
    }

    @Test("Stamping writes the four it is given, on all twelve, and does not touch the id")
    func stampingWritesWhatItIsGiven() throws {
        for shape in Self.everyRecordShape {
            #expect(shape.changesTheFour(Self.first, Self.second), "\(shape.name)")
        }
    }

    @Test("The default flag is written by claiming(isDefault:) and by nothing else")
    func theFlagHasOneWriter() throws {
        let profile = profileRecord(isDefault: true)

        #expect(profile.claiming(isDefault: false).isDefault == false)
        #expect(profile.claiming(isDefault: false).claiming(isDefault: true) == profile)
    }

    @Test("Canonicalising modifiers deduplicates and sorts, and moves nothing else")
    func modifierCanonicalisationIsLocal() throws {
        let messy = setRecord(
            entryID: UUID(),
            modifiers: [SetModifier(.paused), SetModifier(.belt), SetModifier(.paused)])

        let tidy = messy.canonicalisingModifiers()

        #expect(tidy.modifiers.map(\.rawValue) == ["belt", "paused"])
        #expect(tidy.canonicalisingModifiers() == tidy)
        #expect(tidy.weight == messy.weight)
        #expect(tidy.id == messy.id)
    }

    @Test("Writing preferences onto a row keeps the row's id and userID")
    func identityDoesNotTravelWithPreferences() throws {
        let stored = settingsRecord(
            displayUnit: .kilograms,
            theme: .system,
            roundingIncrementGrams: 2500,
            roundingStrategy: .nearest)
        let incoming = settingsRecord(createdAt: Self.first, deletedAt: Self.second)

        let written = incoming.preferencesWritten(onto: stored)

        #expect(written.id == stored.id)
        #expect(written.userID == stored.userID)
        #expect(written.createdAt == stored.createdAt)
        #expect(written.deletedAt == stored.deletedAt)
        #expect(written.displayUnit == .pounds)
        #expect(written.theme == .dark)
        #expect(written.defaultRoundingStrategy == .down)
    }
}
