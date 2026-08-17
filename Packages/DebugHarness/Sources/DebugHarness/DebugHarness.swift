// DebugHarness — the throwaway end-to-end run (DOD-0.3, OUT-0.1).
//
// It seeds the bundled catalogue, logs a short training history against one seeded exercise, reads
// it back through the storage boundary and prints the personal records and estimated one-rep
// maxima that come out. It is the first thing in this repo that touches every layer in one call.
//
// Module-wide rules, stated once here:
//
//   - IT IS DISPOSABLE, AND OUT-0.1 IS WHY. Nothing here is a foundation for Phase 1's UI: no view,
//     no view model, no state that survives the call. When the first real screen exists this package
//     is deleted rather than extended, and nothing can quietly have come to depend on it in the
//     meantime — the manifest is where that is arranged, and says how.
//
//   - IT NAMES NO STORE. The scenario takes two repository protocols, so the executable target is
//     the only thing that decides where rows go and the tests can run the identical scenario
//     against the fakes and against SwiftData. A harness wired directly to `Persistence` would be
//     testable only by running it.
//
//   - THE LOG IS FIXED, AND THE NUMBERS IN IT ARE CHOSEN. `DemonstrationLog` is eight sets over two
//     sessions picked so that every refusal `TR-0.2.5` and `TR-0.2.8` make is visible in the
//     output: a warmup and an abandoned set that hold no record, an N-rep max that is held by a
//     lighter set than the best e1RM, and a rep max carried forward from the older session. Change
//     a number and the point of the run changes with it.
