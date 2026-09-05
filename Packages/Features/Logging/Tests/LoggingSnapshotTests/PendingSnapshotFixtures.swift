#if os(iOS)

    import Foundation
    import PowerliftingCore
    import RepositoryInterface

    // The sets `FR-16.4.1`'s references are taken over. Its own file rather than more of
    // `SessionSnapshotFixtures.swift`, which had reached SwiftLint's file and type-body ceilings.

    extension Fixtures {
        /// A planned workout part-way through: two sets performed, three nobody has reached, and a
        /// failed one (`FR-16.4.1`).
        ///
        /// **All three outcomes in one column, which is what makes the picture worth taking.** The
        /// claim `G-7.3` and `G-4.5` make together is that pending and failed are told apart by two
        /// cues rather than one — the hollow circle against the enclosed cross, and the tertiary
        /// ramp against the negative — and neither is legible in a fixture holding only one of them.
        ///
        /// The pending run is three identical sets, so the collapsed line carries the state as well
        /// as the rows underneath do.
        static let pendingSets: [SetEntry] = [
            loggedSet(index: 40, weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true),
            loggedSet(index: 41, weight: Weight(grams: 100_000), reps: 5, rpe: 8),
            loggedSet(index: 42, weight: Weight(grams: 100_000), reps: 5, rpe: 8),
            loggedSet(index: 43, weight: Weight(grams: 110_000), reps: 5, rpe: nil, isCompleted: false),
            loggedSet(index: 44, weight: Weight(grams: 110_000), reps: 5, rpe: nil, isCompleted: false),
            loggedSet(index: 45, weight: Weight(grams: 110_000), reps: 5, rpe: nil, isCompleted: false),
        ]
    }

#endif
