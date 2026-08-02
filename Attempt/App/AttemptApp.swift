import SwiftUI

/// Composition root (`TR-0.1`).
///
/// This target owns the entry point and dependency wiring, nothing else. Domain logic lives in
/// `PowerliftingCore`, storage in `Persistence`, presentation tokens in `DesignSystem` — all
/// under `Packages/`.
///
/// The packages are not linked here yet: wiring them in is `T-0.03`'s job, once XcodeGen owns
/// the project file and the `.pbxproj` stops being hand-edited.
///
/// `OUT-0.1` puts every screen beyond a throwaway debug harness out of scope for Phase 0, so the
/// scene below is deliberately a placeholder. `T-0.60` replaces it with the harness that seeds
/// data, logs a set, and prints PRs and e1RM (`DOD-0.3`).
@main
struct AttemptApp: App {
    var body: some Scene {
        WindowGroup {
            // Intentionally blank. `OUT-0.1` ships no UI in Phase 0, so an empty scene is the
            // honest representation of that — a placeholder screen would be a screen, and its
            // strings would need localizing (`G-3.4`) for something built to be deleted.
            EmptyView()
        }
    }
}
