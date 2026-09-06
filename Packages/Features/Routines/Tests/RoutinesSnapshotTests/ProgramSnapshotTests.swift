#if os(iOS)

    import DesignSystem
    import DesignTokens
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Routines

    // TR-1.12 for FR-16.8.1's two screens, on the terms `RoutineSnapshotTests` sets out.
    //
    // WHAT A REFERENCE CANNOT SEE HERE: the editor's name and note are `TextField`s, which
    // `ImageRenderer` draws as its unsupported-view placeholder — so what these pin is the rows,
    // their commands, and the two states that carry no field at all.

    @MainActor
    @Suite("Program snapshots")
    struct ProgramSnapshotTests {
        /// The list's two rows, one of them the program in force — the badge is the only thing
        /// separating them and it is drawn at every type size.
        @Test func listRows() throws {
            try assertSnapshots(named: "ProgramList-rows") {
                VStack(alignment: .leading) {
                    ProgramRow(
                        program: ProgramSummary(
                            id: UUID(), name: "Course #2", dayCount: 3, isCurrent: true))
                    ProgramRow(
                        program: ProgramSummary(
                            id: UUID(), name: "Deload block", dayCount: 1, isCurrent: false))
                }
            }
        }

        /// Three 44pt commands beside a day's name, which is the row most at risk at
        /// `accessibility3` — `RoutineCard`'s reason for its own reference.
        @Test func dayCards() throws {
            try assertSnapshots(named: "ProgramEditor-days") {
                VStack(alignment: .leading) {
                    ProgramDayCard(
                        day: ProgramDayRow(
                            id: UUID(), routineID: UUID(), routineName: "Heavy squat day"),
                        index: 0,
                        count: 2,
                        move: { _ in },
                        remove: {})
                    ProgramDayCard(
                        day: ProgramDayRow(id: UUID(), routineID: UUID(), routineName: nil),
                        index: 1,
                        count: 2,
                        move: { _ in },
                        remove: {})
                }
            }
        }

        /// The two states a program with nothing in it shows — `FR-1.13.1`, and the pair a
        /// lifter who has just written their first program sees. The second is the one that
        /// depends on the library rather than on this program, and it is the harder sentence.
        @Test func emptyEditor() throws {
            try assertSnapshots(named: "ProgramEditor-empty") {
                VStack(alignment: .leading) {
                    ProgramDaysSection(days: [], move: { _, _ in }, remove: { _ in })
                    ProgramAddDaySection(choices: [], add: { _ in })
                }
            }
        }

        /// The routines a day can be built from, as a list of buttons rather than a menu — see
        /// ``ProgramAddDaySection`` for why, which is the reason a reference over it means
        /// anything at all.
        @Test func addDayChoices() throws {
            try assertSnapshots(named: "ProgramEditor-add-day") {
                ProgramAddDaySection(
                    choices: [
                        ProgramRoutineChoice(id: UUID(), name: "Heavy squat day"),
                        ProgramRoutineChoice(id: UUID(), name: "Bench and accessories"),
                    ],
                    add: { _ in })
            }
        }
    }

#endif
