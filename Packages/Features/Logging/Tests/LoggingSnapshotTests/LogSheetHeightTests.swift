#if os(iOS)

    import DesignSystem
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // `FR-17.1.6`'s opening height, split out of `LogSheetSnapshotTests.swift` when that file
    // reached SwiftLint's `file_length` — the same reason it was itself split out of
    // `SessionSnapshotTests.swift`. The fixtures stayed there: these are measurements OVER the
    // references' own fixtures, and a second copy of them is how two numbers start describing two
    // different sheets. So this file names `LogSheetSnapshotTests.LogSheetFixtures` throughout and
    // owns no state of its own.

    @MainActor
    @Suite("Log sheet opening heights")
    struct LogSheetHeightTests {
        /// The fixtures these heights are taken over — the references' own, never a second copy.
        typealias LogSheetFixtures = LogSheetSnapshotTests.LogSheetFixtures

        @Test func weightAndRepsOpenAboveTheCommands() throws {
            // FR-17.1.6 asserted on the rendering's own height rather than by eye, on
            // `theFirstSetRowIsInsideTheFirstScreen`'s pattern.
            //
            // THE BUDGET. The smallest device this app supports is 375 × 667 pt and this sheet
            // opens `.large`, so it gets the screen less the status bar. Nothing is subtracted for
            // a navigation bar or a tab bar: a sheet covers both.
            //
            // WHAT IS MEASURED, AND WHY IT IS EXACTLY THE REQUIREMENT. The two regions the sheet
            // stacks in this mode, each rendered as the sheet draws it: `SetEditorHead` — which
            // holds the heading, Weight and Reps and nothing else — and the pinned commands. Sets
            // and the plate row scroll and are not counted, which is `FR-17.1.6`'s own wording: it
            // names Weight and Reps. The pinned plan line is not counted because a checklist row
            // does not draw one — its reference is `PlannedActualPair`, inside the scroll view.
            //
            // THIS IS WHAT PUT THE SHEET AT `.large`. Measured with the plate row still between
            // Weight and Reps the head was 447 pt and the total 648.5 — inside 667 only by the
            // status bar, and over it the moment a label wrapped. Moving that row below the fold
            // brings the head to 352.5 and the total to 554.
            //
            // WHAT IS SUBTRACTED. `Snapshot.render` pads every subject by `Spacing.lg` on all four
            // sides and the sheet does not, so the vertical 32 pt per region is the harness's. The
            // horizontal padding is left where it is, which keeps this conservative: the content is
            // rendered 32 pt narrower than the device would, so more labels wrap here than there.
            let budget = SetEditorSheet.smallestScreen - 20.0
            let regions: [(String, AnyView)] = [
                ("head", AnyView(LogSheetFixtures.head(over: LogSheetFixtures.unanswered))),
                ("commands", AnyView(LogSheetFixtures.commands)),
            ]
            var points = 0.0
            for (name, region) in regions {
                let rendered = try Snapshot.render(
                    fixedEnvironment { region }, appearance: .light, typeSize: .default)
                let height = Double(rendered.height) / Snapshot.scale - 2 * Spacing.lg.points
                print("FR-17.1.6 region \(name): \(height) pt")
                points += height
            }
            print("FR-17.1.6 Log sheet opening height: \(points) pt against a \(budget) pt budget")
            #expect(points < budget)
        }

        @Test func aSecondSectionCostsOneHeadingAndStaysInsideTheBudget() throws {
            // `FR-18.6.2` against `FR-17.1.6`: the claim is about what the budget is measured over,
            // not the sheet's total height. Sections below the first scroll, so all a second
            // section costs the opening height is the *Group 1* heading it gives the first — and
            // this measures that the cost is that and nothing more.
            //
            // THIS ASSERTED `one == two` UNTIL REVIEW, and held because `head(over:)` passed no
            // `sectionTitle` — both arms drew a head with no heading, over a view the sheet does
            // not draw. Measured properly: 352.5 → 389.0 pt at `.default`, 476.0 → 540.0 at
            // `accessibility3`.
            //
            // MEASURED AT BOTH SIZES, AND SO IS THE BUDGET — each against its own device's
            // constant. This read `if typeSize == .default` while `FR-17.1.6` was claimed at the
            // default size only; `FR-18.6.9` claims it at `accessibility3` too, so the guard was
            // an arm that had stopped asserting on its second pass. The constants differ because
            // the devices do (see ``SetEditorSheet/smallestModernSheet``), which is the whole of
            // why this is a `?:` over two literals rather than one budget read twice.
            for typeSize in [SnapshotTypeSize.default, .accessibility3] {
                let one = try Self.headHeight(LogSheetFixtures.unanswered, at: typeSize)
                let two = try Self.headHeight(LogSheetFixtures.twoSections, at: typeSize)
                let commands = try Self.height(
                    LogSheetFixtures.commands(canSave: true), at: typeSize)
                print(
                    "FR-18.6.2 head at \(typeSize): one section \(one) pt, two \(two) pt, "
                        + "commands \(commands) pt")
                // The heading is drawn and it is not free — an equality here is the defect above.
                #expect(two > one)
                // And it is one heading's worth: a second form hoisted into the head would double
                // the three fields, which is far more than the heading plus its own spacing.
                #expect(two - one < one / 2)
                let budget =
                    typeSize == .default
                    ? SetEditorSheet.smallestScreen - 20.0 : SetEditorSheet.smallestModernSheet
                #expect(two + commands < budget)
            }
        }

        @Test func theDisabledStateIsTheOnlyThingThatGrowsTheCommands() throws {
            // The other half of the budget: the **pinned** region, where `Q-18.7`'s line appears.
            // A footer that grows takes the growth out of the scroll view rather than out of the
            // sheet, and the state it appears in is the one where nothing is going to be written
            // — so a lifter logging anything at all never sees it.
            for typeSize in [SnapshotTypeSize.default, .accessibility3] {
                let saving = try Self.height(LogSheetFixtures.commands(canSave: true), at: typeSize)
                let refusing = try Self.height(
                    LogSheetFixtures.commands(canSave: false), at: typeSize)
                print(
                    "FR-18.6.3 commands at \(typeSize): \(saving) pt, disabled \(refusing) pt")
                // Nothing this task added is drawn while the sheet can be saved, so the saveable
                // figure is the one `FR-17.1.6`'s budget was struck against — pinned at both
                // sizes rather than at one, because a `||` on the size is an assertion that stops
                // asserting on its second pass.
                //
                // THE `accessibility3` LITERAL MOVED, 353.0 -> 221.0, AND WHY (`T-18.21`,
                // `Q-18.12`). **Skip this exercise** is no longer pinned at that size — it scrolls
                // at the foot of the form, which is what makes `FR-18.6.9` true: 540 pt of
                // two-section head plus 353 pt of commands was 893 against a 788 pt sheet, and
                // 540 + 221 is 761. The skip's own 132 pt is the whole of the difference. Moved
                // rather than loosened to a range: the number IS the claim, and a range would
                // have held across the change that broke it.
                #expect(saving == (typeSize == .default ? 201.5 : 221.0))
                #expect(refusing > saving)
            }
        }

        @Test func weightAndRepsOpenAtAccessibilitySizes() throws {
            // `DOD-18.14` and `FR-18.6.9`, on `weightAndRepsOpenAboveTheCommands`' pattern and
            // with its two regions — but at `accessibility3`, over the TWO-section head, which is
            // the worst shape a saveable sheet opens in.
            //
            // THE BUDGET IS A DIFFERENT DEVICE'S. `SetEditorSheet.smallestModernSheet` — 788 pt,
            // the iPhone 17e's 844 less the 56 pt a `.large` sheet's top edge sits down the
            // screen. The `.default` arm's 667 is a device no iOS 26 build runs on, so the two
            // claims cannot share a constant.
            //
            // AND WITH THE KEYBOARD DOWN, which is what this sheet now opens with at this size
            // (`Q-18.12`, `FR-18.6.1` narrowed). The pad costs a further ≈306 pt: measured with it
            // up there is less room than the head alone needs, so no budget would hold and the
            // requirement would be false however the commands were arranged.
            //
            // THE TWO HEIGHTS ARE ASSERTED AS WELL AS THE SUM, AND THAT IS WHAT NAMES THE SIZE.
            // Pointed at `.default` this test reads 389.0 + 201.5 = 590.5 against 788 and passes
            // with 197 pt to spare, asserting nothing — `requirements.md` v1.15 asks each
            // assertion to name the size it is made at, and here the figures are how it is named.
            let head = try Self.headHeight(LogSheetFixtures.twoSections, at: .accessibility3)
            let commands = try Self.height(
                LogSheetFixtures.commands(canSave: true), at: .accessibility3)
            print(
                "FR-18.6.9 at accessibility3: head \(head) pt, commands \(commands) pt, "
                    + "total \(head + commands) pt against \(SetEditorSheet.smallestModernSheet)")
            // The two-section head at `accessibility3` — the figure `Q-18.12` was decided on.
            #expect(head == 540.0)
            // **Save as done** and **Cancel**; the skip has gone to the foot of the form.
            #expect(commands == 221.0)
            #expect(head + commands < SetEditorSheet.smallestModernSheet)
        }

        @Test func theSkipJoinsTheFormAtAccessibilitySizes() throws {
            // The other half of the move, and the one no height above can see: the commands
            // getting shorter is not the skip arriving anywhere. A change that dropped it from the
            // footer and never drew it in the form would pass every budget in this file and lose a
            // command (`FR-17.9.6`) at the one size nobody looks at.
            //
            // MEASURED AS A DIFFERENCE rather than against a literal, because what is claimed is
            // that the region grows by the command exactly where the footer stopped drawing it —
            // and the form's own height is four sections of fields that no requirement pins.
            for typeSize in [SnapshotTypeSize.default, .accessibility3] {
                let offering = try Self.height(
                    LogSheetFixtures.form(over: LogSheetFixtures.twoSections, skip: {}),
                    at: typeSize)
                let without = try Self.height(
                    LogSheetFixtures.form(over: LogSheetFixtures.twoSections, skip: nil),
                    at: typeSize)
                print("FR-18.6.9 form at \(typeSize): with skip \(offering) pt, without \(without)")
                if typeSize == .default {
                    // The skip is pinned, so this region does not know it exists: a `skip` handed
                    // to it changes nothing it draws. Asserted rather than assumed, because it is
                    // the half that says the move is a MOVE — a form drawing the command at every
                    // size would leave it in both places and pass the accessibility arm below.
                    #expect(offering == without)
                } else {
                    // And at an accessibility size the region grows by the command arriving in it.
                    //
                    // 136.0 AND NOT THE FOOTER'S 132.0, WHICH IS THE INTERESTING PART. The button
                    // itself is 120 pt at this size; what it costs is that plus the gap of the
                    // stack it joins, and the two stacks do not agree — this form is
                    // `Spacing.lg` (16) and the footer is `Spacing.md` (12). So the move hands the
                    // pinned region back 132 and spends 136, 4 pt more than it saved. That is
                    // free: those 4 pt are inside the scroll view, and `FR-18.6.9`'s budget is
                    // over what the sheet OPENS with — head plus what is pinned, 761 against 788,
                    // which `weightAndRepsOpenAtAccessibilitySizes` asserts unchanged.
                    //
                    // Pinned as a literal rather than as `> 0`, because a difference of any size
                    // would also be satisfied by the command landing here in a smaller emphasis,
                    // or twice, or in a stack it was never meant to join.
                    #expect(offering - without == 136.0)
                }
            }
        }

        /// The height of the region `FR-17.1.6`'s budget is measured over, at one type size.
        ///
        /// - Parameters:
        ///   - sections: What the sheet holds.
        ///   - typeSize: The size the claim is made at — see the caller's note.
        /// - Returns: The height in points, the harness's own padding subtracted.
        static func headHeight(
            _ sections: SetEditorSections, at typeSize: SnapshotTypeSize
        ) throws -> Double {
            try height(LogSheetFixtures.head(over: sections), at: typeSize)
        }

        /// One region's rendered height, the harness's own padding subtracted.
        ///
        /// - Parameters:
        ///   - region: What to measure.
        ///   - typeSize: The size the claim is made at.
        /// - Returns: The height in points.
        static func height(_ region: some View, at typeSize: SnapshotTypeSize) throws -> Double {
            let rendered = try Snapshot.render(
                fixedEnvironment { region }, appearance: .light, typeSize: typeSize)
            return Double(rendered.height) / Snapshot.scale - 2 * Spacing.lg.points
        }
    }

#endif
