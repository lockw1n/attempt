// Deliberate G-7.7 violations. Not compiled, not linted by a normal run — scripts/verify-lint-rules.sh
// names it explicitly and requires all four rules to fire on it.
//
// WHAT THIS FIXTURE PROVES, precisely: that all four G-7.7 rules fire on a file laid out the way a
// feature module will be. It does NOT prove the `Packages/Features/.*` path filter — measured by
// deleting that line from all four rules, which changes nothing here, because a custom rule's
// `included` is matched unanchored against the ABSOLUTE path and this repository's root directory
// is itself named `Attempt`. The .swiftlint.yml comment has the whole argument. The filter becomes
// load-bearing, and this file becomes its proof, only if the matching is ever tightened.
//
// Every construct below is one a real screen reaches for, and every one has a token that replaces
// it. The middle block was added when a probe found four of them escaping all four rules; the
// radius block at the bottom arrived with the fifth rule, and is five shapes rather than one
// because a literal curve can be written five ways (see .swiftlint.yml).
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

            // A style named inside `.system(` leaves the scale without carrying a point size.
            Text("+2.5 since March")
                .font(.system(.title3, design: .rounded))
                // A colour space in front of the components hid these from the colour rule.
                .foregroundStyle(Color(.sRGB, red: 0.2, green: 0.8, blue: 0.3))
            // System semantic colours standing in for textPrimary/textSecondary.
            Text("Last set")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.orange)
        // `minHeight: 44` is the tap-target literal; the rule used to cover width:/height: alone.
        .frame(maxWidth: 320, minHeight: 44)
        // `.shadow(`'s first label is always `color:`, so this walked through the verb list.
        .shadow(color: .black, radius: 4)
        // Five ways to write a literal corner radius, only two of which name RoundedRectangle.
        .cornerRadius(12)
        .background(Color.gray, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 16))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomTrailingRadius: 4))
        .clipShape(RoundedRectangle(cornerSize: CGSize(width: 12, height: 12)))
    }
}
