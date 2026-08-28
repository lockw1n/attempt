import Foundation
import Testing

@testable import Settings

/// `FR-1.10.5`: the two numbers on the About screen are the running build's, read at runtime.
///
/// The suite exists to make the *literal* impossible. Every assertion below anchors one side to a
/// value the test wrote into a bundle or a dictionary, so a lookup that had been quietly replaced
/// by a constant — or one that returned nothing at all — fails rather than reading `nil == nil`.
@Suite("App version")
struct AppVersionTests {
    @Test("Both keys are read, and each is the one it names")
    func readsBothKeys() {
        let version = AppVersion.reading([
            "CFBundleShortVersionString": "2.4",
            "CFBundleVersion": "317",
        ])
        // Anchored to literals in both directions: the short version must not be the build, which
        // is the transposition no `a == b` over two optionals could catch.
        #expect(version.shortVersion == "2.4")
        #expect(version.build == "317")
    }

    @Test("A key the bundle does not declare reads as absent, and takes nothing else with it")
    func oneMissingKeyLeavesTheOther() {
        let noBuild = AppVersion.reading(["CFBundleShortVersionString": "1.0"])
        #expect(noBuild.build == nil)
        // The anchor. A `reading` that gave up and returned an empty value would satisfy the line
        // above and fail this one.
        #expect(noBuild.shortVersion == "1.0")

        let noVersion = AppVersion.reading(["CFBundleVersion": "9"])
        #expect(noVersion.shortVersion == nil)
        #expect(noVersion.build == "9")
    }

    @Test("A bundle declaring nothing at all declares neither")
    func nothingDeclared() {
        #expect(AppVersion.reading(nil) == AppVersion(shortVersion: nil, build: nil))
        #expect(AppVersion.reading([:]) == AppVersion(shortVersion: nil, build: nil))
    }

    @Test("A value that is not a string is refused rather than described")
    func nonStringValuesAreRefused() {
        // A property list is allowed a number under either key. `317` printed from an `Int` would
        // be a version string this app invented, and it would look exactly like a real one.
        let version = AppVersion.reading([
            "CFBundleShortVersionString": 2,
            "CFBundleVersion": 317,
        ])
        #expect(version.shortVersion == nil)
        #expect(version.build == nil)
    }

    @Test("The read goes through a real bundle, not just a dictionary")
    func readsARealBundle() throws {
        // The half `reading(_:)` cannot prove: that `current(in:)` asks the bundle for its
        // `infoDictionary` rather than carrying its own answer.
        let bundle = try Self.bundle(declaring: [
            "CFBundleShortVersionString": "5.1",
            "CFBundleVersion": "42",
        ])
        #expect(AppVersion.current(in: bundle) == AppVersion(shortVersion: "5.1", build: "42"))
    }

    @Test("Two bundles declaring different versions read differently")
    func theAnswerFollowsTheBundle() throws {
        // "Changing the build number updates the screen without a code change", as far as a unit
        // test can put it: nothing here is edited between the two reads but the bundle.
        let first = try Self.bundle(declaring: ["CFBundleVersion": "1"])
        let second = try Self.bundle(declaring: ["CFBundleVersion": "2"])
        #expect(AppVersion.current(in: first).build == "1")
        #expect(AppVersion.current(in: second).build == "2")
    }

    /// A bundle on disk declaring exactly `info`.
    ///
    /// - Parameter info: What its `Info.plist` should say.
    /// - Returns: The bundle.
    private static func bundle(declaring info: [String: Any]) throws -> Bundle {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Fixture.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try PropertyListSerialization
            .data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: root))
    }
}
