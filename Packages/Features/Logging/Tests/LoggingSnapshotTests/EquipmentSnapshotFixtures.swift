#if os(iOS)

    import Foundation
    import PowerliftingCore
    import RepositoryInterface

    // The gyms every equipment reference renders. A file of its own on `SessionSnapshotFixtures`'
    // argument, and shared with the plate calculator's suite: the calculator's references used to
    // render a plate set the app itself supplied, and now that nothing invents one, both suites need
    // the same gym written down somewhere.

    /// The profiles the references in this target draw.
    enum EquipmentFixtures {
        /// A metric competition gym — a 20 kg bar, 2.5 kg collars, and the plates a platform has.
        ///
        /// **Its identifier is fixed rather than fresh**, so a reference rendered twice is the same
        /// picture: nothing here draws an identifier, but a row keyed on one that changed per run
        /// would reorder a list that ties on name.
        static let metricGym = profile(
            id: "11111111-1111-1111-1111-111111111111",
            name: "Home gym",
            bar: 20_000,
            collar: 2_500,
            plates: [
                (25_000, 4), (20_000, 1), (15_000, 1), (10_000, 1), (5_000, 1), (2_500, 1),
                (1_250, 1),
            ]
        )

        /// A second gym, so the list has one row in use and one not: a bare training bar with a
        /// couple of pairs and no collars at all.
        static let travelGym = profile(
            id: "22222222-2222-2222-2222-222222222222",
            name: "The commercial place",
            bar: 15_000,
            collar: 0,
            plates: [(20_000, 2), (10_000, 2)]
        )

        /// A gym the user set up and left unnamed, stocking nothing — both stand-ins on one row.
        static let unnamedGym = profile(
            id: "33333333-3333-3333-3333-333333333333",
            name: "",
            bar: 20_000,
            collar: 0,
            plates: []
        )

        /// One profile record.
        ///
        /// - Parameters:
        ///   - id: Its identifier, spelled out so it does not vary between runs.
        ///   - name: What the user called it, or empty.
        ///   - bar: The bar's mass in grams.
        ///   - collar: The mass of one collar in grams.
        ///   - plates: The denominations in grams, each with how many pairs of it.
        /// - Returns: The record.
        private static func profile(
            id: String,
            name: String,
            bar: Int,
            collar: Int,
            plates: [(Int, Int)]
        ) -> EquipmentProfile {
            EquipmentProfile(
                id: UUID(uuidString: id) ?? UUID(),
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                name: name,
                barWeight: Weight(grams: bar),
                collarWeight: Weight(grams: collar),
                plates: plates.map { Weight(grams: $0.0) },
                platePairCounts: plates.map(\.1),
                isDefault: false
            )
        }
    }

#endif
