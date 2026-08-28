import Foundation

/// The Health-access screen's copy (`G-3.4`), in the same type as the rest of this module's — a
/// third file rather than a third enum, so ``SettingsStrings/all`` stays the module's one list.
extension SettingsStrings {
    /// The Settings row that opens the screen.
    static let healthRow = resource("settings.landing.health.row")

    /// What is behind that row.
    static let healthRowDetail = resource("settings.landing.health.detail")

    /// The screen's own name, which a pushed screen supplies for itself.
    static let healthTitle = resource("settings.health.title")

    /// The heading over the status.
    static let healthStatusTitle = resource("settings.health.status.title")

    /// Nobody has been asked yet.
    static let healthStatusNotAsked = resource("settings.health.status.not-asked")

    /// The question has been put and answered.
    ///
    /// **"Requested", never "granted".** The value is what the app knows; what the person chose is
    /// not disclosed to it — see ``BodyweightSourceAuthorization``.
    static let healthStatusAnswered = resource("settings.health.status.answered")

    /// Why this screen shows a request rather than a grant. Drawn beside **both** determined
    /// statuses, since it is the fact the screen exists to state.
    static let healthDisclosureDetail = resource("settings.health.disclosure.detail")

    /// The heading over where the prompt comes from.
    static let healthPromptTitle = resource("settings.health.prompt.title")

    /// When the prompt is raised, said before it happens (`TR-1.9`).
    static let healthPromptDetail = resource("settings.health.prompt.detail")

    /// What is behind the row that leads to the import.
    static let healthPromptRowDetail = resource("settings.health.prompt.row.detail")

    /// The heading over the way out of the app.
    static let healthChangeTitle = resource("settings.health.change.title")

    /// The command that opens Health.
    static let healthOpenAction = resource("settings.health.change.action")

    /// Where the switch is once Health is open — Health lands on its own summary and publishes no
    /// deeper link, so the remaining taps are written out. **It stops at Health's app list without
    /// claiming this app is in it**; the catalogue entry has the measurement behind that.
    static let healthChangePath = resource("settings.health.change.path")

    /// Nothing on this device accepted Health's own URL, so the command did not go anywhere.
    ///
    /// **It names the way in that does not depend on a URL scheme**, because the one thing it
    /// cannot do is repeat the command that just failed.
    static let healthOpenFailed = resource("settings.health.change.failed")

    /// The heading where this device has no health source at all.
    static let healthUnavailableHeadline = resource("settings.health.unavailable.headline")

    /// What that means, in the user's terms.
    static let healthUnavailableMessage = resource("settings.health.unavailable.message")

    /// The heading where the source would not say.
    static let healthUnknownHeadline = resource("settings.health.unknown.headline")

    /// What that means, and that trying again may work.
    static let healthUnknownMessage = resource("settings.health.unknown.message")

    /// The Health screen's keys, for the test that proves each one resolves.
    static var allHealthStrings: [LocalizedStringResource] {
        [
            healthRow, healthRowDetail, healthTitle, healthStatusTitle, healthStatusNotAsked,
            healthStatusAnswered, healthDisclosureDetail, healthPromptTitle, healthPromptDetail,
            healthPromptRowDetail, healthChangeTitle, healthOpenAction, healthChangePath,
            healthOpenFailed,
            healthUnavailableHeadline, healthUnavailableMessage, healthUnknownHeadline,
            healthUnknownMessage,
        ]
    }
}
