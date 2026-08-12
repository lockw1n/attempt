import Foundation
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

/// ``withTemporaryStore(_:)`` for an async body — the repositories are actors, so every call into
/// them suspends.
func withTemporaryStore(_ body: (URL) async throws -> Void) async throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "T042-\(UUID().uuidString)")
        .appendingPathExtension("store")
    defer {
        for suffix in ["", "-shm", "-wal"] {
            let path = url.path(percentEncoded: false) + suffix
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
    }
    try await body(url)
}

@Suite("The container and the stack")
struct PersistenceStackTests {
    @Test("A stack over a real file writes a row the store keeps")
    func theStackOpensTheRealStore() async throws {
        try await withTemporaryStore { url in
            let stack = try PersistenceStack(location: .file(url))
            try await stack.exercises.save(exerciseRecord(name: "Back Squat"))

            let rows = try ModelContext(try makeModelContainer(at: .file(url)))
                .fetch(FetchDescriptor<ExerciseEntity>())
            #expect(rows.map(\.name) == ["Back Squat"])
        }
    }

    @Test("A second stack on the same file reads what the first wrote")
    func theStoreOutlivesTheStack() async throws {
        try await withTemporaryStore { url in
            let first = try PersistenceStack(location: .file(url))
            try await first.exercises.save(exerciseRecord(name: "Deadlift"))

            let second = try PersistenceStack(location: .file(url))
            #expect(
                try await second.exercises.exercises(includingDeleted: false).map(\.name)
                    == ["Deadlift"])
        }
    }

    @Test("The five repositories over one container see each other's writes")
    func theRepositoriesShareTheStore() async throws {
        let harness = try RepositoryHarness()
        let exercise = exerciseRecord()
        try await harness.stack.exercises.save(exercise)
        let session = sessionRecord()
        try await harness.stack.workouts.save(session)

        // The workout repository's own context has to see a row the exercise repository wrote, or
        // this save is refused as a dangling reference.
        try await harness.stack.workouts.save(
            entryRecord(sessionID: session.id, exerciseID: exercise.id))

        #expect(
            try await harness.stack.workouts.entries(
                forSessionID: session.id, includingDeleted: false
            ).count == 1)
    }

    @Test("An in-memory store is not shared between containers")
    func inMemoryStoresAreIsolated() async throws {
        let first = try RepositoryHarness()
        try await first.stack.exercises.save(exerciseRecord())

        let second = try RepositoryHarness()
        #expect(try await second.stack.exercises.exercises(includingDeleted: false).isEmpty)
    }

    @Test("No repository method performs network I/O")
    func nothingReachesTheNetwork() throws {
        // G-2.2, checked the only way a test can: the module names nothing that could. A repository
        // that grew a fetch would have to import one of these first.
        let sources = FileManager.default.enumerator(
            atPath: repositorySourceRoot.path(percentEncoded: false))
        var offenders: [String] = []
        while let relative = sources?.nextObject() as? String {
            guard relative.hasSuffix(".swift") else { continue }
            let text = try String(
                contentsOf: repositorySourceRoot.appending(path: relative), encoding: .utf8)
            for banned in ["URLSession", "URLRequest", "Network.", "import Network"]
            where text.contains(banned) {
                offenders.append("\(relative): \(banned)")
            }
        }
        #expect(offenders.isEmpty, "network I/O in the persistence layer: \(offenders)")
    }
}

/// `Sources/Persistence/`, found from this file rather than from the working directory — `swift
/// test` and `xcodebuild` do not agree about what that is.
let repositorySourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // PersistenceTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // Persistence (package)
    .appending(path: "Sources/Persistence")
