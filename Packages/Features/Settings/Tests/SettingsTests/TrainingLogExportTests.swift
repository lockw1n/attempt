import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Settings

/// `FR-1.11.1`/`FR-1.11.2`: what an export reads out of the store, and the two files it writes.
@Suite("Training log export")
struct TrainingLogExportTests {
    @Test("It gathers every level of the log")
    func gathersTheWholeLog() async throws {
        let log = try await ExportLog.populated()
        _ = try await log.bodyweight(grams: 82_400)
        let archive = try await log.export.archive(exportedAt: ExportLog.epoch)
        #expect(archive.exercises.count == 1)
        #expect(archive.sessions.count == 1)
        #expect(archive.entries.count == 1)
        #expect(archive.sets.count == 3)
        #expect(archive.bodyweight.count == 1)
        #expect(archive.exportedAt == ExportLog.epoch)
    }

    @Test("A deleted set is not in the file, and neither is a deleted session")
    func leavesOutWhatWasDeleted() async throws {
        let log = ExportLog()
        let squat = try await log.exercise(named: "Back Squat")
        let kept = try await log.session(daysAgo: 0)
        let keptEntry = try await log.entry(squat, in: kept)
        _ = try await log.set(in: keptEntry, order: 0, grams: 100_000, reps: 5)
        let removedSet = try await log.set(in: keptEntry, order: 1, grams: 110_000, reps: 3)
        try await log.repositories.workouts.deleteSet(id: removedSet.id)

        let discarded = try await log.session(daysAgo: 1)
        let discardedEntry = try await log.entry(squat, in: discarded, order: 0)
        _ = try await log.set(in: discardedEntry, order: 0, grams: 90_000, reps: 5)
        try await log.repositories.workouts.deleteSession(id: discarded.id)

        let archive = try await log.export.archive()
        // Anchored to what is left rather than only to what is gone: an export that returned
        // nothing at all would satisfy every "is not present" assertion here.
        #expect(archive.sessions.map(\.id) == [kept.id])
        #expect(archive.sets.count == 1)
        #expect(archive.sets.first?.weight == Weight(grams: 100_000))
        #expect(archive.sets.allSatisfy { $0.deletedAt == nil })
    }

    @Test("An untrained store is empty however many exercises it holds")
    func seededCatalogueIsNotALog() async throws {
        let log = ExportLog()
        _ = try await log.exercise(named: "Back Squat")
        _ = try await log.exercise(named: "Bench Press")
        let archive = try await log.export.archive()
        #expect(archive.exercises.count == 2)
        #expect(archive.isEmpty)
    }

    @Test("Both files are written, named for the day, and the CSV opens as UTF-8")
    func writesBothFiles() async throws {
        let log = try await ExportLog.populated()
        let scratch = ScratchDirectory()
        let archive = try await log.export.archive(exportedAt: ExportLog.epoch)
        let files = try TrainingLogExportWriter.write(
            archive,
            unit: .kilograms,
            into: scratch.url,
            timeZone: .gmt)

        #expect(files.csv.lastPathComponent == "Attempt-training-log-2025-07-06.csv")
        #expect(files.json.lastPathComponent == "Attempt-training-log-2025-07-06.json")
        #expect(files.sessionCount == 1)
        #expect(files.setCount == 3)

        let csv = try Data(contentsOf: files.csv)
        // The BOM is what makes a note outside ASCII survive Excel. It is on the file rather than
        // in the rendered text, so the text a parser sees is the text the renderer's tests assert.
        #expect(csv.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        #expect(String(data: csv.dropFirst(3), encoding: .utf8)?.hasPrefix("date,") == true)

        let restored = try TrainingLogArchive.decoded(from: Data(contentsOf: files.json))
        #expect(restored == archive)
    }

    @Test("A second export into the same directory replaces the first")
    func doesNotHandOnYesterdaysFile() async throws {
        let log = try await ExportLog.populated()
        let scratch = ScratchDirectory()
        let stale = try TrainingLogExportWriter.write(
            try await log.export.archive(exportedAt: ExportLog.epoch),
            unit: .kilograms,
            into: scratch.url,
            timeZone: .gmt)

        // A day later, and a set lighter — the names differ, so without emptying the directory the
        // share sheet would still be offered a file describing a log that has moved on.
        let last = try #require(try await log.export.archive().sets.last)
        try await log.repositories.workouts.deleteSet(id: last.id)
        let fresh = try TrainingLogExportWriter.write(
            try await log.export.archive(exportedAt: ExportLog.epoch.addingTimeInterval(86_400)),
            unit: .kilograms,
            into: scratch.url,
            timeZone: .gmt)

        #expect(fresh.setCount == 2)
        #expect(!FileManager.default.fileExists(atPath: stale.csv.path))
        #expect(FileManager.default.fileExists(atPath: fresh.csv.path))
        #expect(fresh.csv.lastPathComponent == "Attempt-training-log-2025-07-07.csv")
    }
}
