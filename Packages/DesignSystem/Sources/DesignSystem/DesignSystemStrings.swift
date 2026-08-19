import Foundation

/// The copy this module owns (`G-3.4`), and the only place a `DesignSystem` string literal is
/// written.
///
/// **A component owns a string only when that string is the same on every screen it appears on.**
/// "Try again" and the offline explanation are affordances of the app, not of the screen behind
/// them; a headline naming what is missing belongs to the screen and arrives as a `Text` the caller
/// built. Splitting it anywhere else would either put twelve copies of "Try again" in twelve
/// catalogues or put domain knowledge in here.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` and binds it to this module's
/// own bundle. The key convention itself is documented once, in `Localization`.
///
/// `nonisolated`, unlike most of this module: ``StateKind`` maps a state to its copy and is itself
/// nonisolated, so the constants have to be reachable off the main actor. They are immutable and
/// `Sendable`, so there is nothing for the isolation to protect.
nonisolated enum DesignSystemStrings {
    /// The fallback heading over a failure the caller did not name.
    static let errorHeadline = resource("designsystem.error.headline")

    /// The retry out of a failed or offline state — the one string two kinds share.
    static let retry = resource("designsystem.state.retry")

    /// What VoiceOver announces while a read is in flight. A spinner has no text of its own, so
    /// without this the state is silent (`G-4.2`).
    static let loadingLabel = resource("designsystem.loading.accessibility-label")

    /// The heading over the no-connection state.
    static let offlineHeadline = resource("designsystem.offline.headline")

    /// The offline explanation, which has to say that logged work is unaffected (`G-2.1`).
    static let offlineMessage = resource("designsystem.offline.message")

    /// The fallback heading over a derived value that cannot be computed yet (`FR-1.13.3`).
    static let insufficientDataHeadline = resource("designsystem.insufficient-data.headline")

    /// Every string this module can show, for the test that proves each one resolves.
    static var all: [LocalizedStringResource] {
        [
            errorHeadline, retry, loadingLabel, offlineHeadline, offlineMessage,
            insufficientDataHeadline,
        ]
    }

    /// Binds a key to this module's catalogue.
    private static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
