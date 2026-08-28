import Foundation

/// What the running build says it is (`FR-1.10.5`).
///
/// **Read from the bundle, never written down.** The About screen's whole obligation is that the
/// two numbers on it are the binary's own, so a literal anywhere in this module would be the defect
/// this type exists to prevent — `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` reach the app
/// through `GENERATE_INFOPLIST_FILE`, and nothing in Swift needs editing when either moves.
///
/// Two levels, which is what makes it testable: ``current(in:)`` names a bundle, ``reading(_:)``
/// takes the info dictionary the keys actually live in. A test cannot install a version into
/// `Bundle.main`, that bundle being the test runner rather than the app.
///
/// **Both fields are optional because both keys are.** Only the app target declares them, so the
/// absent case is real everywhere else and is drawn rather than papered over — a screen that
/// substituted "1.0" for a missing key would be reporting a version nobody built.
struct AppVersion: Equatable, Sendable {
    /// `CFBundleShortVersionString`: the version a lifter would quote in a bug report.
    let shortVersion: String?

    /// `CFBundleVersion`: which build of that version this is.
    let build: String?

    /// What a bundle declares about itself.
    ///
    /// - Parameter bundle: Defaults to the running app's.
    /// - Returns: Its version and build, each `nil` where the bundle declares none.
    static func current(in bundle: Bundle = .main) -> AppVersion {
        reading(bundle.infoDictionary)
    }

    /// The same lookup, over the dictionary the two keys live in.
    ///
    /// **A non-string value reads as absent rather than as its description.** A property list is
    /// allowed to hold a number under either key, and `1` printed from an `Int` would be a version
    /// string this app invented rather than one the build declared.
    ///
    /// - Parameter info: A bundle's `infoDictionary`.
    /// - Returns: What it declares.
    static func reading(_ info: [String: Any]?) -> AppVersion {
        AppVersion(
            shortVersion: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String)
    }
}
