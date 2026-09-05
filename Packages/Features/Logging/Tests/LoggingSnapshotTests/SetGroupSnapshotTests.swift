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

        @Test func setGroupLogNext() throws {
            // `FR-16.1.4`, and `FR-16.6.4` with it. What the picture settles is three claims the
            // requirement makes together: the command sits under a group that has a count to tick
            // — a `× 3` line, which is why the fixture is the one ending in a run rather than
            // `groupedSets` and its lone final set — it is attached to the *last* working group and
            // to no other, and it is drawn secondary at `G-4.3`'s 60pt logging extent, the screen's
            // one accent being left for **Finish workout**. At `accessibility3` it is also where
            // the full-width label has to survive a two-line wrap.
            try assertSnapshots(named: "Session-set-groups-log-next") {
                fixedEnvironment {
                    groupRows(Fixtures.groupedSetsEndingInARun, logsNext: true)
                }
            }
        }

        @Test func pendingSets() throws {
            // `FR-16.4.1` with `G-7.3` and `G-4.5`. What the picture settles is that a set nobody
            // attempted is not drawn as a missed lift: the run of three carries a hollow circle in
            // the tertiary ramp where the failed set would carry an enclosed cross in the negative
            // one, and its numbers are quieter than the performed sets above it rather than red.
            // At `accessibility3` it is also where the three states have to stay distinguishable
            // once the row becomes a stack.
            try assertSnapshots(named: "Session-set-pending") {
                fixedEnvironment { groupRows(Fixtures.pendingSets, isSessionOpen: true) }
            }
        }

        @Test func pendingSetsExpanded() throws {
            // The run opened (`FR-16.1.3`). T-16.01's trap in its own reference: a per-set
            // annotation drawn only on the collapsed line is invisible on the member rows, and one
            // drawn only on the member rows is invisible until the run is asked for. Pending is on
            // both, so this is what proves the second half — three hollow circles under the line
            // that already carries one.
            try assertSnapshots(named: "Session-set-pending-expanded") {
                fixedEnvironment {
                    groupRows(
                        Fixtures.pendingSets,
                        expanded: Set(Fixtures.pendingSets.suffix(3).map(\.id)),
                        isSessionOpen: true)
                }
            }
        }

        @Test func pendingSetsAfterFinish() throws {
            // The same sets in a workout that has ended — the one column that changed is the
            // session's, and every uncompleted set is now a failed one. The pair with the picture
            // above is the whole of "pending is derived, and Finish is what converts it".
            try assertSnapshots(named: "Session-set-pending-finished") {
                fixedEnvironment { groupRows(Fixtures.pendingSets, isSessionOpen: false) }
            }
        }

        /// A column of `FR-16.1.1`'s groups, partitioned and numbered the way the card does it.
        ///
        /// - Parameters:
        ///   - sets: The sets, in the order they were logged.
        ///   - expanded: Which groups are open (`FR-16.1.3`).
        ///   - schemes: Which cells each set holds a record at (`FR-16.2.4`).
        ///   - logsNext: Whether the last working group carries `FR-16.1.4`'s append, as the card
        ///     hands it out — to that group and to no other.
        ///   - isSessionOpen: Whether the workout has yet to end (`FR-16.4.1`).
        /// - Returns: The lines.
        private func groupRows(
            _ sets: [SetEntry],
            expanded: Set<UUID> = [],
            schemes: [UUID: [RecordScheme]] = [:],
            logsNext: Bool = false,
            isSessionOpen: Bool = false
        ) -> some View {
            let numbered = SetNumbering.numbered(sets)
            let working = SetNumbering.grouped(numbered.filter { !$0.isWarmup })
            let groups = SetNumbering.grouped(numbered.filter(\.isWarmup)) + working
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
                        recordSchemes: { schemes[$0] ?? [] },
                        isSessionOpen: isSessionOpen,
                        logNext: logsNext && group.id == working.last?.id ? {} : nil
                    )
                }
            }
        }
    }

#endif
