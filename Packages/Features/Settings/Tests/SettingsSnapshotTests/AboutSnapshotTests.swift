#if os(iOS)

    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Settings

    // TR-1.12 for FR-1.10.5. The reading rather than the screen, this package's standing shape —
    // `ImageRenderer` draws none of a `ScrollView`'s content, so a reference through `AboutView`
    // would be a reference of an empty page.
    //
    // THE COPY IS THE SUBJECT HERE, as it is on the Health screen. This one has no data and no
    // states: what these references pin is the privacy policy itself, which is the document
    // FR-1.10.5 asks for and which ships inside the build rather than behind a link. A sentence
    // here changing is a change to what this app tells a lifter it does with their training, and
    // it should not be able to happen without a reference moving.
    //
    // THE VERSION IS SUPPLIED, NOT READ. Under a test bundle `Bundle.main` is the runner and
    // declares neither key, so a reference taken through `AppVersion.current()` would pin the
    // absent case twice and say nothing about the ordinary one.

    @MainActor
    @Suite("About snapshots")
    struct AboutSnapshotTests {
        @Test func about() throws {
            // The ordinary screen: a version and a build the bundle declared.
            try assertSnapshots(named: "About") {
                AboutReading(version: AppVersion(shortVersion: "1.0", build: "1"))
            }
        }

        @Test func versionUnknown() throws {
            // A bundle declaring neither key. Not a state — the screen has none — but the one
            // value on it that can be absent, and the reference is what says it reads as a word
            // rather than as a blank or an invented number.
            try assertSnapshots(named: "About-version-unknown") {
                AboutReading(version: AppVersion(shortVersion: nil, build: nil))
            }
        }
    }

#endif
