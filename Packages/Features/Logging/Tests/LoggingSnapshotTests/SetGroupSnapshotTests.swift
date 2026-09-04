#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for `FR-16.1.1`'s set groups. A suite of its own rather than more of
    // `SessionSnapshotTests`, which had reached SwiftLint's file and type-body ceilings: the two grow
    // for different reasons — a screen state being added, and a way of reading sets being added.

    @MainActor
    @Suite("Set group snapshots")
    struct SetGroupSnapshotTests {
        @Test func setGroups() throws {
            // The collapsed reading: `100 kg × 6 × 4` on one line, the range badge, the rating and
            // the outcome drawn once — and beneath it the fifth set, which is a row rather than a
            // group of one. The warmup pair above it is the same rule inside `FR-1.2.14`'s fold,
            // which is where the `W1–2` badge is checked.
            try assertSnapshots(named: "Session-set-groups") {
                fixedEnvironment { groupRows(Fixtures.groupedSets) }
            }
        }

        @Test func setGroupExpanded() throws {
            // `FR-16.1.3`: the same column with the working group open. What the picture settles is
            // that the rows underneath are the ordinary `SetRow` — badge, values and outcome all
            // drawn as controls — so every per-set field is one tap from the collapsed line.
            try assertSnapshots(named: "Session-set-groups-expanded") {
                fixedEnvironment {
                    groupRows(Fixtures.groupedSets, expanded: [Fixtures.groupedSets[2].id])
                }
            }
        }

        @Test func setGroupRecordBadge() throws {
            // `FR-16.2.4`: the badge names the maximal scheme the run set. The working group of four
            // carries **PR 6×4** and the lone fifth set **PR 6RM** — two spellings of one badge, and
            // the picture is what settles that the collapsed line has room for both beside the
            // rating and the numbers it already draws.
            try assertSnapshots(named: "Session-set-groups-record") {
                fixedEnvironment {
                    groupRows(Fixtures.groupedSets, schemes: Fixtures.recordSchemes)
                }
            }
        }

        /// A column of `FR-16.1.1`'s groups, partitioned and numbered the way the card does it.
        ///
        /// - Parameters:
        ///   - sets: The sets, in the order they were logged.
        ///   - expanded: Which groups are open (`FR-16.1.3`).
        ///   - schemes: Which cells each set holds a record at (`FR-16.2.4`).
        /// - Returns: The lines.
        private func groupRows(
            _ sets: [SetEntry],
            expanded: Set<UUID> = [],
            schemes: [UUID: [RecordScheme]] = [:]
        ) -> some View {
            let numbered = SetNumbering.numbered(sets)
            let groups =
                SetNumbering.grouped(numbered.filter(\.isWarmup))
                + SetNumbering.grouped(numbered.filter { !$0.isWarmup })
            return VStack(alignment: .leading) {
                ForEach(groups) { group in
                    SetGroupRow(
                        group: group,
                        unit: .kilograms,
                        isExpanded: expanded.contains(group.id),
                        toggle: {},
                        mark: { _, _ in },
                        markCompleted: { _, _ in },
                        edit: { _ in },
                        recordSchemes: { schemes[$0] ?? [] }
                    )
                }
            }
        }
    }

#endif
