import DesignSystem
import Foundation
import SwiftUI

/// About: what this build is, whose work is in it, and what it does with the lifter's data
/// (`FR-1.10.5`).
///
/// **The one screen in Settings with nothing behind it.** There is no store to read and no
/// authorization to ask after, so it has none of `FR-1.13.1`'s five phases — everything on it is
/// either a fact about the running bundle or a sentence that ships with the binary.
///
/// **The privacy policy is drawn here rather than linked out to.** No hosted document exists, and a
/// URL pointing at one that does not is precisely the placeholder `G-5.3` cannot afford: the App
/// Privacy label has to be accurate at every submission, and a policy inside the app is versioned
/// by the same build number the section above it prints. The App Store listing still needs a
/// reachable URL of its own, which belongs to the task that submits.
///
/// The view half of the pattern: it owns the bundle read, and everything drawable belongs to
/// ``AboutReading``. There is no injecting seam here — under `swift test` `Bundle.main` is the
/// runner and declares neither key, so a version reaches a reference through ``AboutReading`` or
/// not at all.
public struct AboutView: View {
    /// What the running build says it is, read once when the screen is constructed.
    private let version = AppVersion.current()

    /// Builds the screen over the running bundle.
    public init() {}

    /// The three sections, scrolling.
    public var body: some View {
        ScrollView {
            AboutReading(version: version)
                .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(SettingsStrings.aboutTitle))
    }
}

/// What the About screen draws — `TR-1.12`'s renderable half.
///
/// No `ScrollView` here, this module's other screens' reason: `ImageRenderer` draws none of one's
/// content.
struct AboutReading: View {
    /// What the running build says it is.
    let version: AppVersion

    /// The build, the acknowledgements, the policy — in that order, because the policy's last line
    /// refers back to the version.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            build
            acknowledgements
            privacy
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The two numbers, each read from the bundle at runtime.
    private var build: some View {
        GroupedSection(Text(SettingsStrings.aboutVersionTitle)) {
            row(SettingsStrings.aboutVersionLabel, version.shortVersion)
            row(SettingsStrings.aboutBuildLabel, version.build)
        }
    }

    /// Whose work is in here. Two sentences: the licences there are none of, and the published
    /// formulas there are.
    private var acknowledgements: some View {
        GroupedSection(Text(SettingsStrings.aboutAcknowledgementsTitle)) {
            paragraph(SettingsStrings.aboutAcknowledgementsCode)
            paragraph(SettingsStrings.aboutAcknowledgementsFormulas)
        }
    }

    /// The policy itself: where the log lives, what Health is read for, what is measured, and why
    /// this text is current.
    private var privacy: some View {
        GroupedSection(Text(SettingsStrings.aboutPrivacyTitle)) {
            paragraph(SettingsStrings.aboutPrivacyStorage)
            paragraph(SettingsStrings.aboutPrivacyHealth)
            paragraph(SettingsStrings.aboutPrivacyTracking)
            paragraph(SettingsStrings.aboutPrivacyCurrency)
        }
    }

    /// One labelled value from the bundle.
    ///
    /// **The value is verbatim.** A version is an identifier rather than a quantity, so putting it
    /// through a number format would group `10000` and localize its separator — `1.0` is not one
    /// point zero.
    ///
    /// - Parameters:
    ///   - label: What the number is.
    ///   - value: What the bundle declared, or `nil` where it declared nothing.
    /// - Returns: The row.
    private func row(_ label: LocalizedStringResource, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm.points) {
            Text(label)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
            Spacer(minLength: Spacing.sm.points)
            (value.map(Text.init(verbatim:)) ?? Text(SettingsStrings.aboutVersionUnknown))
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// One sentence of the copy.
    ///
    /// - Parameter text: What to say.
    /// - Returns: The paragraph.
    private func paragraph(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
