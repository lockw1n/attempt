// Deliberate G-3.4 violations. Not compiled, not linted by a normal run — scripts/verify-lint-rules.sh
// names it explicitly and requires no_literal_ui_strings to fire on it.
//
// WHAT THIS FIXTURE PROVES: that every shape a screen actually reaches for when it writes copy is
// caught. The rule is an enumerated list of the SwiftUI entry points that take user-visible text,
// so the probe that matters is the API's OTHER spellings rather than the ones the regex was built
// from — the same lesson no_magic_corner_radius learned when UnevenRoundedRectangle's second
// initializer walked through the rule written for that very type.
//
// The `verbatim:` block is the one a reader may misread as a false positive. It is not: the ban is
// on a verbatim LITERAL, which is copy that can never be translated. Text(verbatim: someValue),
// which renders a stored identifier or a formatted number, is legal and is in the negative fixture.
import SwiftUI

struct LiteralCopyFixture: View {
    let value: String

    var body: some View {
        VStack {
            Text("Estimated max")
            Text(verbatim: "1RM")
            Button("Start workout") {}
            Label("Add set", systemImage: "plus")
            Toggle("Warm-up", isOn: .constant(true))
            TextField("Notes", text: .constant(""))
            SecureField("Passcode", text: .constant(""))
            Link("Open the manual", destination: URL(string: "https://example.com")!)
            Section("Recent") { EmptyView() }
            NavigationLink("History") { EmptyView() }
            DisclosureGroup("Details") { EmptyView() }
            ContentUnavailableView("No sessions", systemImage: "tray")
            Stepper("Reps", value: .constant(5))
            Picker("Unit", selection: .constant(0)) { EmptyView() }
            LabeledContent("Estimator", value: value)
            Menu("More") { EmptyView() }
            GroupBox("Volume") { EmptyView() }
            Tab("Train", systemImage: "figure.strengthtraining.traditional") { EmptyView() }
        }
        .navigationTitle("Settings")
        .navigationSubtitle("Preferences")
        .navigationBarTitle("Settings")
        .help("Choose the unit weights are shown in")
        .accessibilityLabel("Display unit")
        .accessibilityHint("Switches between kilograms and pounds")
        .accessibilityValue("Kilograms")
        .badge("New")
        .alert("Could not save", isPresented: .constant(false)) { EmptyView() }
        .confirmationDialog("Delete this set?", isPresented: .constant(false)) { EmptyView() }
        .searchable(text: .constant(""), prompt: "Search exercises")
        .toolbar { ToolbarItem { Text("Done") } }
    }

    // The labelled-argument shapes, which reach copy without naming a SwiftUI type at all.
    func rows() -> [String] {
        [
            row(title: "Units", message: "Kilograms or pounds"),
            row(titleKey: "Estimator", description: "Epley"),
            row(label: "Bar", labelKey: "Barbell"),
            row(prompt: "Search", placeholder: "Exercise name"),
            row(header: "Today", footer: "Tap to log"),
        ]
    }

    func row(title: String, message: String) -> String { title + message }

    // Neither of these is a literal at a call site, and both are the bug the catalogue exists to
    // prevent: with no bundle they resolve against Bundle.main, which in a package is the app's
    // catalogue and has no such key. The user sees the key name.
    func wrongBundle() -> String {
        let resource = LocalizedStringResource("settings.landing.units.title")
        return String(localized: "settings.landing.units.picker") + String(localized: resource)
    }
}
