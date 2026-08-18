// The satisfiable half of no_literal_ui_strings — scripts/verify-lint-rules.sh requires this file
// to produce ZERO violations of it. A rule that nothing can satisfy reads as a working gate right
// up to the point where every screen is in violation and the catalogue is unusable, which is the
// failure TokenUsageFixture.swift guards one dimension over.
//
// Four legal shapes live here, and each is one a real screen needs:
//
//   Text(Strings.x)                  copy, from the module's own catalogue. The accessors below
//                                    name the bundle, which is what keeps them out of the rule's
//                                    last alternative — a resource that names no bundle resolves
//                                    against Bundle.main and finds nothing.
//   Text(verbatim: value)            a stored identifier or an already-formatted number. Not copy,
//                                    and not translatable — the ban is on a verbatim LITERAL.
//   accessibilityIdentifier("...")   a test hook. It is not user-visible and must never be
//                                    translated; a rule that fired here would be telling the author
//                                    to localise a UI-test selector.
//   Image(systemName: "..."), Image("...")
//                                    an SF Symbol name and an asset name. Both are identifiers that
//                                    happen to be strings.
//
// The doc comment below is the fifth thing this file proves: `match_kinds` keeps the rule off
// prose. Without it, a comment quoting Text("Units") — which is exactly how the rule gets explained
// — fires the rule on the file explaining it.
import SwiftUI

/// A screen whose copy is in the catalogue. Writing `Text("Units")` here instead is the violation,
/// and `.navigationTitle("Settings")` is the same mistake one modifier over.
struct CatalogCopyFixture: View {
    let value: String

    var body: some View {
        VStack {
            Text(FixtureStrings.unitsTitle)
            Text(verbatim: value)
            Label { Text(FixtureStrings.addSet) } icon: { Image(systemName: "plus") }
            Image("barbell")
        }
        .accessibilityIdentifier("settings-landing")
        .navigationTitle(Text(FixtureStrings.unitsTitle))
    }
}

enum FixtureStrings {
    static let unitsTitle = LocalizedStringResource(
        "settings.landing.units.title", bundle: .atURL(Bundle.module.bundleURL))
    static let addSet = LocalizedStringResource(
        "logging.session.add-set", bundle: .atURL(Bundle.module.bundleURL))
}
