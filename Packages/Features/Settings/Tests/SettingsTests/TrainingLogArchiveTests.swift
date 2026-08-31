import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Settings

/// `FR-1.11.1`'s JSON half: structured, and lossless in the word's own sense.
@Suite("Training log archive")
struct TrainingLogArchiveTests {
    /// A stamp with a sub-second component. It is the whole subject of this suite.
    static let stamp = Date(timeIntervalSinceReferenceDate: 773_452_800.123_456_7)

    /// Every record type, every optional populated, and values chosen to break a lazy encoder: a
    /// sub-second timestamp, a negative load, an unknown modifier, a note with a quote and a
    /// newline in it.
    ///
    /// - Returns: The archive.
    static func awkwardArchive() -> TrainingLogArchive {
        let exerciseID = ExportRecords.id(0x11)
        let sessionID = ExportRecords.id(0x22)
        let entryID = ExportRecords.id(0x33)
        return TrainingLogArchive(
            exportedAt: stamp,
            exercises: [awkwardExercise(exerciseID, parent: sessionID)],
            sessions: [awkwardSession(sessionID, references: entryID, and: exerciseID)],
            entries: [
                ExportRecords.entry(
                    id: entryID,
                    sessionID: sessionID,
                    exerciseID: exerciseID,
                    at: stamp,
                    order: 3,
                    notes: "paused")
            ],
            sets: [awkwardSet(entryID)],
            bodyweight: [
                BodyweightEntry(
                    id: ExportRecords.id(0x55),
                    createdAt: stamp,
                    updatedAt: stamp,
                    deletedAt: nil,
                    date: stamp,
                    weight: Weight(grams: 82_400),
                    source: .healthKit)
            ])
    }

    /// An exercise with every optional filled and a name a naïve writer would mangle.
    private static func awkwardExercise(_ id: UUID, parent: UUID) -> Exercise {
        Exercise(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            name: "Chin-up \"wide\"",
            ukrainianName: "Підтягування \"широким хватом\"",
            movement: .other,
            parentExerciseID: parent,
            equipment: .machine,
            laterality: .unilateral,
            barType: .safetySquat,
            implementCount: 2,
            isCustom: true,
            isArchived: true,
            notes: "a\nnote",
            manualE1RM: Weight(grams: 140_000))
    }

    /// A session with its bodyweight and both programme references present.
    private static func awkwardSession(
        _ id: UUID,
        references run: UUID,
        and scheduled: UUID
    ) -> WorkoutSession {
        WorkoutSession(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            date: stamp,
            startedAt: stamp,
            endedAt: stamp,
            notes: "hot, humid",
            bodyweight: Weight(grams: 82_400),
            programRunID: run,
            scheduledWorkoutID: scheduled)
    }

    /// A set with a negative load, both targets, both ratings, and a modifier nothing recognises.
    private static func awkwardSet(_ entryID: UUID) -> SetEntry {
        SetEntry(
            id: ExportRecords.id(0x44),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            entryID: entryID,
            order: 7,
            weight: Weight(grams: -22_500),
            reps: 12,
            rpe: 9.5,
            rir: 0,
            isWarmup: true,
            isCompleted: false,
            targetWeight: Weight(grams: 100_000),
            targetReps: 5,
            modifiers: [SetModifier(.belt), SetModifier(rawValue: "knee sleeves, blue")],
            notes: "said \"stop\"",
            completedAt: stamp)
    }

    @Test("Encoding and decoding reproduces every field")
    func roundTripsLosslessly() throws {
        let archive = Self.awkwardArchive()
        let restored = try TrainingLogArchive.decoded(from: archive.encoded())
        // Equality is the whole claim, but a failure on the struct says only "not equal", so the
        // date is asserted separately: it is the field the strategy was chosen for.
        #expect(restored.sets.first?.createdAt == Self.stamp)
        #expect(restored == archive)
    }

    // `FR-1.11.3`/`FR-1.11.4`. A backup is the one artefact both name fields have to survive in,
    // and the interesting case is a catalogue that holds some of each — an archive whose exercises
    // are all translated would pass for a writer that filled the column in on restore.
    @Test("Both name fields survive a backup, set and unset alike")
    func bothNamesSurviveTheArchive() throws {
        let translated = Self.awkwardExercise(ExportRecords.id(0x71), parent: ExportRecords.id(0x72))
        let untranslated = Exercise(
            id: ExportRecords.id(0x72),
            createdAt: Self.stamp,
            updatedAt: Self.stamp,
            deletedAt: nil,
            name: "Back Squat",
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: "",
            manualE1RM: nil)
        let archive = TrainingLogArchive(
            exportedAt: Self.stamp,
            exercises: [translated, untranslated],
            sessions: [],
            entries: [],
            sets: [],
            bodyweight: [])

        let restored = try TrainingLogArchive.decoded(from: archive.encoded())

        // Anchored to the literals rather than to the fixture, so two empty catalogues cannot agree.
        #expect(
            restored.exercises.map(\.ukrainianName)
                == ["Підтягування \"широким хватом\"", nil])
        #expect(restored.exercises.map(\.name) == ["Chin-up \"wide\"", "Back Squat"])
    }

    @Test("A timestamp survives to the sub-second, which is what picked the strategy")
    func datesAreExactRatherThanRounded() throws {
        let restored = try TrainingLogArchive.decoded(from: Self.awkwardArchive().encoded())
        let back = try #require(restored.sessions.first).createdAt
        // Anchored to a literal rather than to the fixture's own value in both places: `a == b`
        // over two values from one source passes when the source returns nothing interesting.
        #expect(Self.stamp.timeIntervalSinceReferenceDate != 773_452_800)
        #expect(back.timeIntervalSinceReferenceDate == 773_452_800.123_456_7)
    }

    @Test("The keys are written in sorted order, which is what makes two runs agree")
    func keyOrderIsStable() throws {
        // Encoding twice in one process cannot see this, and an assertion that did would pass
        // whatever the encoder is configured for: Swift fixes a dictionary's order with a
        // per-process seed, so an unsorted encoder agrees with itself all run and disagrees with
        // tomorrow's — which is the only case `.sortedKeys` exists for. The bytes are the witness.
        let json = try #require(String(data: Self.awkwardArchive().encoded(), encoding: .utf8))
        #expect(
            Self.envelopeKeys(of: json) == [
                "bodyweight", "contents", "entries", "exercises", "exportedAt", "formatVersion",
                "sessions", "sets",
            ])
    }

    /// The envelope's own keys, in the order the file carries them.
    ///
    /// Internal rather than private because ``BackupArchiveTests`` asks the same question of the
    /// backup's longer key list, and one reader of the bytes is what makes the two answers
    /// comparable.
    ///
    /// A pretty-printed payload indents two spaces per level, so a key of the envelope is a line
    /// carrying exactly one level of it — which is what separates `bodyweight` the section from
    /// `bodyweight` the column on a session.
    static func envelopeKeys(of json: String) -> [String] {
        json.split(separator: "\n")
            .filter { $0.hasPrefix("  \"") }
            .map { String($0.dropFirst(3).prefix { $0 != "\"" }) }
    }

    @Test("An unknown modifier is carried verbatim rather than resolved away")
    func preservesTheLiftersOwnWords() throws {
        let restored = try TrainingLogArchive.decoded(from: Self.awkwardArchive().encoded())
        let modifiers = try #require(restored.sets.first).modifiers.map(\.rawValue)
        #expect(modifiers == ["belt", "knee sleeves, blue"])
    }

    @Test("The envelope names its format version, and it survives the round trip")
    func carriesItsFormatVersion() throws {
        let archive = Self.awkwardArchive()
        let json = try #require(String(data: archive.encoded(), encoding: .utf8))
        #expect(json.contains("\"formatVersion\""))
        #expect(try TrainingLogArchive.decoded(from: archive.encoded()).formatVersion == 2)
        #expect(TrainingLogArchive.currentFormatVersion == 2)
    }

    @Test("The file is written to be looked at: pretty, and its sections in a fixed order")
    func isReadableAndOrdered() throws {
        let json = try #require(String(data: Self.awkwardArchive().encoded(), encoding: .utf8))
        #expect(json.contains("\n"))
        let exercises = try #require(json.range(of: "\"exercises\""))
        let sessions = try #require(json.range(of: "\"sessions\""))
        #expect(exercises.lowerBound < sessions.lowerBound)
    }

    @Test("Emptiness is the log, never the catalogue")
    func emptinessIgnoresSeededExercises() {
        let seeded = TrainingLogArchive(
            exportedAt: .distantPast,
            exercises: Self.awkwardArchive().exercises,
            sessions: [],
            entries: [],
            sets: [],
            bodyweight: [])
        #expect(seeded.isEmpty)
        #expect(!Self.awkwardArchive().isEmpty)
    }

    @Test("A reading with nothing trained is still a log")
    func emptinessCountsBodyweight() {
        // `isEmpty`'s other half. A lifter can weigh in for a week before their first session, and
        // an export that called that nothing would refuse to hand over rows it is holding.
        let weighedOnly = TrainingLogArchive(
            exportedAt: .distantPast,
            exercises: [],
            sessions: [],
            entries: [],
            sets: [],
            bodyweight: Self.awkwardArchive().bodyweight)
        #expect(!weighedOnly.bodyweight.isEmpty)
        #expect(!weighedOnly.isEmpty)
    }
}
