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

    @Test("A replacement swaps the file rather than rewriting the one already there")
    func replacingAnEntryIsAtomic() throws {
        let temp = TemporaryCache()
        try temp.cache.write(try formulasPayload(revision: 1), for: .formulas)
        let before = try inodeNumber(of: temp.cache.fileURL(for: .formulas))

        try temp.cache.write(try formulasPayload(revision: 2), for: .formulas)

        // An atomic write lands in a temporary file and is renamed over the old one, so the file's
        // identity changes; a plain write truncates the old file and keeps it. That is the only
        // difference a caller can observe, and it is the whole of what stops an interrupted write
        // from leaving half a payload where a good one was.
        #expect(try inodeNumber(of: temp.cache.fileURL(for: .formulas)) != before)
    }

    @Test("A removed entry reads as a miss")
    func removedEntryReadsAsNil() throws {
        let temp = TemporaryCache()
        try temp.cache.write(try formulasPayload(revision: 4), for: .formulas)
        temp.cache.remove(.formulas)
        #expect(temp.cache.data(for: .formulas) == nil)
    }

    @Test("Removing what was never there is not a failure")
    func removingAMissingEntryIsHarmless() throws {
        let temp = TemporaryCache()
        try temp.cache.write(try formulasPayload(revision: 4), for: .formulas)
        temp.cache.remove(.flags)
        #expect(temp.cache.data(for: .formulas) != nil)
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
