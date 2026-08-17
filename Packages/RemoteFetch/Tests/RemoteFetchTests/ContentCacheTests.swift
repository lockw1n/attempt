import Foundation
import Testing

@testable import RemoteFetch

@Suite("ContentCache")
struct ContentCacheTests {
    @Test("A written payload reads back byte for byte")
    func writeThenReadRoundTrips() throws {
        let temp = TemporaryCache()
        let payload = try formulasPayload(revision: 4)
        try temp.cache.write(payload, for: .formulas)
        #expect(temp.cache.data(for: .formulas) == payload)
    }

    @Test("An empty cache is a miss, not a failure")
    func missingEntryReadsAsNil() {
        let temp = TemporaryCache()
        #expect(temp.cache.data(for: .formulas) == nil)
    }

    @Test("The directory is created by the first write, not by construction")
    func directoryIsCreatedOnFirstWrite() throws {
        let temp = TemporaryCache()
        #expect(!FileManager.default.fileExists(atPath: temp.cache.directory.path))
        try temp.cache.write(try formulasPayload(revision: 1), for: .formulas)
        #expect(FileManager.default.fileExists(atPath: temp.cache.directory.path))
    }

    @Test("Each resource writes to its own file")
    func entriesDoNotShareAFile() throws {
        let temp = TemporaryCache()
        try temp.cache.write(try formulasPayload(revision: 4), for: .formulas)
        #expect(temp.cache.data(for: .flags) == nil)
        #expect(temp.cache.fileURL(for: .formulas).lastPathComponent == RemoteResource.formulas.cacheFileName)
    }

    @Test("A write that cannot make its directory throws rather than losing the payload silently")
    func writeThrowsWhenTheDirectoryCannotExist() throws {
        let occupied = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteFetchTests-occupied-\(UUID().uuidString)", isDirectory: false)
        try Data("not a directory".utf8).write(to: occupied)
        defer { try? FileManager.default.removeItem(at: occupied) }

        let cache = ContentCache(directory: occupied)
        #expect(throws: (any Error).self) {
            try cache.write(try formulasPayload(revision: 1), for: .formulas)
        }
    }

    @Test("The default directory is a private corner of the caches directory")
    func defaultDirectoryIsUnderCaches() throws {
        let directory = try ContentCache.defaultDirectory()
        #expect(directory.pathComponents.suffix(2) == ["RemoteContent", "v1"])
        #expect(directory.path.contains("Caches"))
    }
}
