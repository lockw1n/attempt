#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for T-1.30's screen. A file of its own on `SessionNoteSnapshotTests`' argument: the
    // session suite is already at `file_length`, and this one grows with the plate calculator.
    //
    // The subject is `PlateCalculatorContent` rather than `PlateCalculatorSheet`, for the reason the
    // set editor's references give: `ImageRenderer` lays a `ScrollView`'s content out and draws none
    // of it, so a reference over the sheet would be a picture of a navigation bar. The content takes
    // values rather than the store, so no reference here needs the `.task` the renderer cannot run.

    @MainActor
    @Suite("Plate calculator snapshots")
    struct PlateCalculatorSnapshotTests {
        // MARK: - The plate calculator (FR-1.4.1, FR-1.4.4)

        @Test func exactLoading() throws {
            // FR-1.4.1: a target that loads, with the fractional plate that forces the finer display
            // step — the reference is what stops `1.25 kg` regressing to `1.5 kg`.
            try assertSnapshots(named: "Plate-exact") {
                fixedEnvironment {
                    try? content(target: Weight(grams: 102_500))
                }
            }
        }

        @Test func nearestEitherSide() throws {
            // FR-1.4.4: both arms present, each with its own plates.
            try assertSnapshots(named: "Plate-nearest") {
                fixedEnvironment {
                    try? content(target: Weight(grams: 101_000))
                }
            }
        }

        @Test func nothingLoadsAbove() throws {
            // FR-1.13.3 through FR-1.4.4: the gym's plates do not reach the target, so the upper arm
            // is the insufficient-data state and the lower one is still a real loading.
            try assertSnapshots(named: "Plate-unreachable") {
                fixedEnvironment {
                    try? content(target: Weight(grams: 400_000))
                }
            }
        }

        @Test func unusableEquipment() throws {
            // The error state with no retry — the target still drawn above it, because it is the
            // user's own number and does not depend on the read.
            try assertSnapshots(named: "Plate-unusable") {
                fixedEnvironment {
                    PlateCalculatorContent(
                        target: Weight(grams: 102_500),
                        state: .unusable,
                        equipment: nil,
                        unit: .kilograms,
                        retry: {},
                        chooseEquipment: {}
                    )
                }
            }
        }

        @Test func editorRow() throws {
            // FR-1.4.1's entry point, in the set editor: the per-side line for the weight the form
            // holds, and the tap that opens the screen above.
            try assertSnapshots(named: "Plate-row") {
                fixedEnvironment {
                    PlateLoadingRow(
                        target: Weight(grams: 102_500),
                        result: try? Self.calculator().loading(for: Weight(grams: 102_500)),
                        unit: .kilograms,
                        open: {}
                    )
                }
            }
        }

        @Test func noEquipment() throws {
            // FR-1.13.1's empty state, which replaced the interim plate set this screen used to fall
            // back to: nothing was read, nothing failed, and the action is the only thing that makes
            // a gym.
            try assertSnapshots(named: "Plate-no-equipment") {
                fixedEnvironment {
                    PlateCalculatorContent(
                        target: Weight(grams: 102_500),
                        state: .noEquipment,
                        equipment: nil,
                        unit: .kilograms,
                        retry: {},
                        chooseEquipment: {}
                    )
                }
            }
        }

        /// The screen over the metric gym below, at one target.
        ///
        /// - Parameter target: The weight being loaded for.
        /// - Returns: The content, ready to render.
        private func content(target: Weight) throws -> some View {
            PlateCalculatorContent(
                target: target,
                state: .ready,
                equipment: LoadedEquipment(
                    profile: EquipmentFixtures.metricGym,
                    calculator: try Self.calculator()
                ),
                unit: .kilograms,
                retry: {},
                chooseEquipment: {}
            )
        }

        /// That gym's calculator, projected the same way the store projects it.
        private static func calculator() throws -> PlateCalculator {
            let profile = EquipmentFixtures.metricGym
            return try #require(
                PlateCalculator(
                    bar: profile.barWeight,
                    collar: profile.collarWeight,
                    inventory: try profile.inventory()
                ))
        }
    }

#endif
