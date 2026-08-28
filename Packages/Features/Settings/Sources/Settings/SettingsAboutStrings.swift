import Foundation

/// The About screen's copy (`G-3.4`), in the same type as the rest of this module's — a fourth file
/// rather than a fourth enum, so ``SettingsStrings/all`` stays the module's one list.
extension SettingsStrings {
    /// The Settings section that opens the screen.
    static let aboutSectionTitle = resource("settings.landing.about.title")

    /// The row itself.
    static let aboutRow = resource("settings.landing.about.row")

    /// What is behind that row.
    static let aboutDetail = resource("settings.landing.about.detail")

    /// The screen's own name, which a pushed screen supplies for itself.
    static let aboutTitle = resource("settings.about.title")

    /// The heading over what the running build is.
    static let aboutVersionTitle = resource("settings.about.version.title")

    /// The label beside `CFBundleShortVersionString`.
    static let aboutVersionLabel = resource("settings.about.version.short")

    /// The label beside `CFBundleVersion`.
    static let aboutBuildLabel = resource("settings.about.version.build")

    /// What stands in where the bundle declares neither key.
    ///
    /// **A word and not a substituted number.** Only the app target declares these, so this is what
    /// the screen says outside it rather than a version the app made up.
    static let aboutVersionUnknown = resource("settings.about.version.unknown")

    /// The acknowledgements heading (`FR-1.10.5`).
    static let aboutAcknowledgementsTitle = resource("settings.about.acknowledgements.title")

    /// That there is no third-party code to license.
    ///
    /// **Measured rather than asserted**: no manifest in this repo declares a remote package, and
    /// the snapshot harness is a target of this repo's own. Whichever task adds the first
    /// dependency owns replacing this sentence with the licence it brings.
    static let aboutAcknowledgementsCode = resource("settings.about.acknowledgements.code")

    /// What is third-party here: the published work the estimators implement.
    static let aboutAcknowledgementsFormulas = resource("settings.about.acknowledgements.formulas")

    /// The privacy heading.
    static let aboutPrivacyTitle = resource("settings.about.privacy.title")

    /// Where the training log lives (`G-2.1`, `OUT-0.2`).
    static let aboutPrivacyStorage = resource("settings.about.privacy.storage")

    /// What is read from Health and what is not (`G-5.4`).
    static let aboutPrivacyHealth = resource("settings.about.privacy.health")

    /// That nothing is measured and nobody is told (`G-5.1`, `G-5.2`).
    static let aboutPrivacyTracking = resource("settings.about.privacy.tracking")

    /// Why this document is current: it ships in the build named above it.
    static let aboutPrivacyCurrency = resource("settings.about.privacy.currency")

    /// This screen's share of ``SettingsStrings/all``.
    static var allAboutStrings: [LocalizedStringResource] {
        [
            aboutSectionTitle, aboutRow, aboutDetail, aboutTitle,
            aboutVersionTitle, aboutVersionLabel, aboutBuildLabel, aboutVersionUnknown,
            aboutAcknowledgementsTitle, aboutAcknowledgementsCode, aboutAcknowledgementsFormulas,
            aboutPrivacyTitle, aboutPrivacyStorage, aboutPrivacyHealth, aboutPrivacyTracking,
            aboutPrivacyCurrency,
        ]
    }
}
