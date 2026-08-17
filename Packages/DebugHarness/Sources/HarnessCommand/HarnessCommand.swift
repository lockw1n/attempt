import DebugHarness
import Foundation
import Persistence

/// The one command `DOD-0.3` asks for:
///
/// ```
/// swift run --package-path Packages/DebugHarness attempt-harness
/// ```
///
/// It seeds the bundled catalogue into a fresh store, logs two sessions against a seeded exercise,
/// and prints the personal records and estimated one-rep maxima that come back out.
///
/// **The store is in-memory, and that is the whole of the store decision.** A command-line process
/// has its own application-support directory, so a run against `.applicationDefault` would neither
/// touch the app's store nor prove anything about it — it would only leave a file behind. What the
/// run does exercise either way is the real `ModelContainer`, the real schema and the real
/// repositories; `G-2.2`'s on-disk half is the one thing it does not, and no arrangement of this
/// target could have covered it.
@main
struct HarnessCommand {
    /// Runs the scenario, prints the report, and exits non-zero on anything thrown.
    static func main() async {
        do {
            let stack = try PersistenceStack(location: .inMemory)
            let report = try await HarnessScenario(
                exercises: stack.exercises,
                workouts: stack.workouts
            ).run()
            print(report.text)
        } catch {
            FileHandle.standardError.write(Data("attempt-harness: \(error)\n".utf8))
            exit(1)
        }
    }
}
