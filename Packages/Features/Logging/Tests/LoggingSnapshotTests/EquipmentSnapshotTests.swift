#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for T-1.31's two screens. A file of its own on `PlateCalculatorSnapshotTests`'
    // argument, and the subjects are the two `…Content` types rather than the screens: `ImageRenderer`
    // lays a `ScrollView`'s content out and draws none of it, so a reference over either screen would
    // be a picture of a navigation bar.

    @MainActor
    @Suite("Equipment profile snapshots")
    struct EquipmentSnapshotTests {
        // MARK: - The gyms (FR-1.4.3, FR-1.10.3)

        @Test func profileList() throws {
            // Two gyms, one in use, plus one left unnamed and stocking nothing — every stand-in the
            // list can need, on one reference.
            try assertSnapshots(named: "Equipment-list") {
                fixedEnvironment {
                    list(
                        profiles: [
                            EquipmentFixtures.metricGym, EquipmentFixtures.travelGym,
                            EquipmentFixtures.unnamedGym,
                        ],
                        activeProfileID: EquipmentFixtures.metricGym.id
                    )
                }
            }
        }

        @Test func noProfiles() throws {
            // FR-1.13.2's first-launch state: nothing has been set up, and the action is the only
            // thing that makes a gym.
            try assertSnapshots(named: "Equipment-empty") {
                fixedEnvironment {
                    list(profiles: [], activeProfileID: nil, state: .empty)
                }
            }
        }

        @Test func writeFailed() throws {
            // The list survives a failed write, which is what makes the next attempt a tap.
            try assertSnapshots(named: "Equipment-write-failed") {
                fixedEnvironment {
                    list(
                        profiles: [EquipmentFixtures.metricGym],
                        activeProfileID: EquipmentFixtures.metricGym.id,
                        writeFailure: "recordNotFound(id: 0000)"
                    )
                }
            }
        }

        // MARK: - The editor (FR-1.4.2)

        @Test func editorOverAStoredGym() throws {
            try assertSnapshots(named: "Equipment-editor") {
                fixedEnvironment {
                    EquipmentProfileEditorContent(
                        draft: .constant(
                            EquipmentProfileDraft(
                                editing: EquipmentFixtures.metricGym,
                                unit: .kilograms,
                                locale: Fixtures.locale
                            )),
                        unit: .kilograms
                    )
                }
            }
        }

        @Test func editorOverANewGym() throws {
            // Nothing is prefilled, which is `G-6.2` rather than an oversight: a form opening on a
            // 20 kg bar would be a claim about the user's gym that the user did not make.
            try assertSnapshots(named: "Equipment-editor-new") {
                fixedEnvironment {
                    EquipmentProfileEditorContent(
                        draft: .constant(
                            EquipmentProfileDraft(unit: .kilograms, locale: Fixtures.locale)),
                        unit: .kilograms
                    )
                }
            }
        }

        /// The list at one state.
        ///
        /// - Parameters:
        ///   - profiles: The gyms to draw.
        ///   - activeProfileID: Which one is in use.
        ///   - state: Which of `FR-1.13.1`'s states to draw. Defaults to the loaded one.
        ///   - writeFailure: The diagnostic over the list, where there is one.
        /// - Returns: The content, ready to render.
        private func list(
            profiles: [EquipmentProfile],
            activeProfileID: UUID?,
            state: EquipmentProfilesScreenState = .ready,
            writeFailure: String? = nil
        ) -> some View {
            EquipmentProfilesContent(
                state: state,
                profiles: profiles,
                activeProfileID: activeProfileID,
                unit: .kilograms,
                writeFailure: writeFailure,
                add: {},
                edit: { _ in },
                use: { _ in },
                retry: {}
            )
        }
    }

#endif
