// Deliberate G-7.7 violations. Not compiled, not linted by a normal run — scripts/verify-lint-rules.sh
// names it explicitly and requires all four rules to fire on it.
//
// It exists because the three original fixtures all sit under scripts/lint-fixtures/Attempt/, and
// the rules carry TWO path filters. A green run proved the `Attempt/.*` one worked and said nothing
// whatsoever about `Packages/Features/.*` — the filter that has to hold for every feature module
// Phase 1 adds. This file is that path.
import SwiftUI

struct LiteralValuesFixture: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Estimated max")
                .font(.system(size: 17))
                .foregroundStyle(.red)
            Text("142.5")
                .font(.title)
                .foregroundStyle(Color(red: 1, green: 0.48, blue: 0.1))
        }
        .padding(16)
        .background(Color.orange)
    }
}
