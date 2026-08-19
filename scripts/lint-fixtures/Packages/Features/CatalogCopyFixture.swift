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
//   Text(verbatim: Sample.name)      preview and fixture DATA. A literal bound to a named constant
//                                    is data; the same literal written at the copy call site is
//                                    copy. That line is the rule's one deliberate escape hatch —
//                                    see the Localization module doc, which states it — and a
//                                    preview showing sample exercises is why it exists.
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
            Text(verbatim: Sample.exerciseName)
            Label { Text(FixtureStrings.addSet) } icon: { Image(systemName: "plus") }
            Image("barbell")
        }
        .accessibilityIdentifier("settings-landing")
        .navigationTitle(Text(FixtureStrings.unitsTitle))
    }
}

/// Preview data. Not copy: it stands in for a row the store would supply, and translating it
/// would be translating a barbell's name into a language the catalogue never ships.
enum Sample {
    static let exerciseName = "Low-bar back squat"
}

enum FixtureStrings {
    static let unitsTitle = LocalizedStringResource(
        "settings.landing.units.title", bundle: .atURL(Bundle.module.bundleURL))
    static let addSet = LocalizedStringResource(
        "logging.session.add-set", bundle: .atURL(Bundle.module.bundleURL))
}
