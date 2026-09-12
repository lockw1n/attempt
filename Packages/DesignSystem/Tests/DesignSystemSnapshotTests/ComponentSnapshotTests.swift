#if os(iOS)

    import DesignTokens
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import DesignSystem

    // TR-1.12: every T-1.03 component and every T-1.09 state, in four configurations each — light and
    // dark (`G-7.1`), default and `accessibility3` (`NFR-1.10`'s own ceiling).
    //
    // Every string here is `Text(verbatim:)`. A snapshot that resolved a key would be a snapshot of the
    // catalogue as well as of the layout, and would move whenever the copy did — `DesignSystemStrings`
    // has its own tests for the keys, and this file is about pixels. The exception is the copy a
    // component owns and the caller cannot pass in (the offline explanation, "Try again"): that copy is
    // part of what the component renders, so it renders here too.

    @MainActor
    @Suite("Component snapshots")
    struct ComponentSnapshotTests {
        @Test func card() throws {
            try assertSnapshots(named: "Card-base") {
                Card {
                    Text(verbatim: "Card content")
                }
            }
        }

        @Test func cardRaised() throws {
            try assertSnapshots(named: "Card-raised") {
                Card(elevation: .raised) {
                    Text(verbatim: "Raised content")
                }
            }
        }

        @Test func groupedSection() throws {
            try assertSnapshots(named: "GroupedSection") {
                GroupedSection(Text(verbatim: "Section")) {
                    Text(verbatim: "First row")
                    Text(verbatim: "Second row")
                }
            }
        }

        @Test func metricTileWithContext() throws {
            try assertSnapshots(named: "MetricTile-with-context") {
                Card {
                    MetricTile(label: Text(verbatim: "Squat e1RM"), value: Text(verbatim: "142.5 kg")) {
                        DeltaIndicator(.increase, value: "2.5 kg")
                    }
                }
            }
        }

        /// `G-4.1`'s wrap, in the component's own suite rather than only in a host's.
        ///
        /// **The fixture is the Dashboard's shape, deliberately.** `MetricTile-with-context` above
        /// carries a `DeltaIndicator` alone — short, so it neither truncated before the fix nor
        /// changed after it, and a suite holding only that pictures a tile the fix does nothing to.
        /// What `T-1.82` measured is the line *following* a delta: two context children, the second
        /// a phrase long enough to need a second line at `accessibility3`.
        ///
        /// **The container is the host's, and that is the half that makes it fail.** The same tile
        /// alone in a `Card` is wide enough that the phrase fits on one line, so the fix does
        /// nothing to it and the reference pins nothing — measured, by deleting the modifier and
        /// watching that version pass. `GroupedSection`'s insets are what narrow it to where the
        /// wrap is needed.
        ///
        /// Both of `MetricTile`'s `fixedSize` modifiers are pinned here, each probed by deletion:
        /// the `context`'s, which is `G-4.1`'s wrap, and the numeral's, which is what stops the
        /// flexible `Text` paying for the inflexible sibling (`G-7.5`). Only the `accessibility3`
        /// pair moves — at default Dynamic Type the phrase fits, which is why the defect was
        /// invisible until the accessibility pass.
        @Test func metricTileContextWraps() throws {
            try assertSnapshots(named: "MetricTile-context-wraps") {
                GroupedSection(Text(verbatim: "Estimated maxes")) {
                    MetricTile(
                        label: Text(verbatim: "Barbell Back Squat"),
                        value: Text(verbatim: "182.5 kg")
                    ) {
                        DeltaIndicator(.increase, value: "2.5 kg")
                        Text(verbatim: "Training max 175.0 kg")
                    }
                }
            }
        }

        @Test func metricTileValueOnly() throws {
            try assertSnapshots(named: "MetricTile-value-only") {
                Card {
                    MetricTile(label: Text(verbatim: "Sessions"), value: Text(verbatim: "18"))
                }
            }
        }

        @Test func primaryActionIntrinsic() throws {
            try assertSnapshots(named: "PrimaryAction-intrinsic") {
                Button {
                } label: {
                    Text(verbatim: "Start session")
                }
                .buttonStyle(.primaryAction)
            }
        }

        @Test func primaryActionFill() throws {
            try assertSnapshots(named: "PrimaryAction-fill") {
                Button {
                } label: {
                    Text(verbatim: "Start session")
                }
                .buttonStyle(.primaryAction(.fill))
            }
        }

        // G-4.4: the disabled fade is below the contrast floor on purpose, and that is exactly why it is
        // snapshotted — a change that made it *look* enabled would otherwise be invisible here.
        @Test func primaryActionDisabled() throws {
            try assertSnapshots(named: "PrimaryAction-disabled") {
                Button {
                } label: {
                    Text(verbatim: "Start session")
                }
                .buttonStyle(.primaryAction(.fill))
                .disabled(true)
            }
        }

        // FR-16.6.4: the pair is the whole point — a secondary action is the primary one at the
        // same size and the same shape, differing only in its fill, so a screen can carry three
        // commands and still spend `G-7.2`'s one accent once. Snapshotted beside it rather than
        // alone, because what has to stay true is the relationship.
        @Test func secondaryActionFill() throws {
            try assertSnapshots(named: "SecondaryAction-fill") {
                VStack(spacing: Spacing.lg.points) {
                    Button {
                    } label: {
                        Text(verbatim: "Finish workout")
                    }
                    .buttonStyle(.primaryAction(.fill))
                    Button {
                    } label: {
                        Text(verbatim: "Log next set")
                    }
                    .buttonStyle(.secondaryAction(.fill))
                }
            }
        }

        @Test func secondaryActionIntrinsic() throws {
            try assertSnapshots(named: "SecondaryAction-intrinsic") {
                Button {
                } label: {
                    Text(verbatim: "Repeat set")
                }
                .buttonStyle(.secondaryAction)
            }
        }

        @Test(arguments: [DeltaDirection.increase, .decrease, .unchanged])
        func delta(_ direction: DeltaDirection) throws {
            try assertSnapshots(named: "Delta-\(direction)") {
                DeltaIndicator(direction, value: "2.5 kg")
            }
        }
    }

    @MainActor
    @Suite("State snapshots")
    struct StateSnapshotTests {
        @Test func empty() throws {
            try assertSnapshots(named: "State-empty") {
                EmptyStateView(
                    headline: Text(verbatim: "No exercises yet"),
                    message: Text(verbatim: "Add one to start logging."),
                    action: StateAction(Text(verbatim: "Add exercise"), emphasis: .primary) {}
                )
            }
        }

        // `FR-16.6.4`'s two weights, as a picture. The emphasis is compile-enforced now — the
        // parameter has no default — but nothing else proves the secondary case is not the primary
        // one drawn twice, and the choice is invisible from the call site's own type.
        @Test func emptySecondaryAction() throws {
            try assertSnapshots(named: "State-empty-secondary") {
                EmptyStateView(
                    headline: Text(verbatim: "No exercises yet"),
                    message: Text(verbatim: "Add one to start logging."),
                    action: StateAction(Text(verbatim: "Add exercise"), emphasis: .secondary) {}
                )
            }
        }

        // READ THE COMMITTED IMAGE BEFORE READING A DIFF OF IT. `ImageRenderer` cannot rasterise a
        // `ProgressView` — it is UIKit-backed, and the renderer draws its unsupported-view placeholder
        // (a yellow prohibition sign) in its place. The reference is therefore deterministic and green,
        // and it pins this state's copy, spacing and alignment, but it does NOT pin the spinner's
        // appearance or its true size. A spinner that regressed would not be caught here; that
        // observation needs a hosted view, like the two VoiceOver ones this task also hands on.
        @Test func loading() throws {
            try assertSnapshots(named: "State-loading") {
                LoadingStateView(message: Text(verbatim: "Reading from Health"))
            }
        }

        @Test func error() throws {
            try assertSnapshots(named: "State-error") {
                ErrorStateView(message: Text(verbatim: "That could not be saved."), retryEmphasis: .primary, retry: {})
            }
        }

        // The same state with no handler. Its pair above is what makes the action button's *rendering*
        // observable — see StateActionRenderingTests.
        @Test func errorWithoutRetry() throws {
            try assertSnapshots(named: "State-error-no-retry") {
                ErrorStateView(message: Text(verbatim: "That could not be saved."))
            }
        }

        @Test func offline() throws {
            try assertSnapshots(named: "State-offline") {
                OfflineStateView(retryEmphasis: .primary, retry: {})
            }
        }

        @Test func insufficientData() throws {
            try assertSnapshots(named: "State-insufficient-data") {
                InsufficientDataView(message: Text(verbatim: "Log two more sets to see a trend."))
            }
        }

        // FR-16.5.4's field, in both of the states it has. The empty one is the whole of what the
        // requirement asks for — a search affordance visible without a gesture — and the filled one
        // is the only picture of the clear control, which is drawn only when there is something to
        // clear. One reference, because the pair is the claim.
        //
        // The prompt is `verbatim` and not this module's copy: a component must not know a screen's
        // words, which is why the caller supplies them.
        @Test func searchField() throws {
            try assertSnapshots(named: "SearchField") {
                VStack(alignment: .leading, spacing: Spacing.md.points) {
                    SearchField(text: .constant(""), prompt: "Search exercises")
                    SearchField(text: .constant("front squat"), prompt: "Search exercises")
                }
            }
        }
    }

#endif
