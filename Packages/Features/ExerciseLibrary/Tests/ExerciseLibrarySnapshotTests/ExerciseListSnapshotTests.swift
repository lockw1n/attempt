#if os(iOS)

    import DesignSystem
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import ExerciseLibrary

    // TR-1.12 for this module's screen: what the exercise list renders, in four configurations each
    // — light and dark (`G-7.1`), default and `accessibility3` (`NFR-1.10`'s own ceiling).
    //
    // WHAT IS RENDERED AND WHAT IS NOT. The pieces, not `ExerciseListView` itself: the screen owns a
    // `.task` that reads a store and a `.searchable` field the enclosing `NavigationStack` places,
    // and `ImageRenderer` has neither. Between them these eight references cover every pixel the
    // screen has of its own — the grouped catalogue with and without archived rows, the filter chips
    // in all three of their states, the show-archived control in both of its, and the four
    // placeholders it can show instead.
    //
    // A ROW'S TEXT IS DIMMER HERE THAN IT IS IN THE APP, and that is the rendering rather than the
    // screen: a `NavigationLink` with no `NavigationStack` above it draws as though it led nowhere.
    // Wrapping the subject in one does not help — measured: a `NavigationStack` is UIKit-backed, so
    // `ImageRenderer` draws the unsupported-view placeholder and the whole list disappears. These
    // references are therefore a regression baseline rather than a picture of the shipped colours;
    // the colours are what the simulator run checks (`docs/phase-1/tasks.md` §2).
    //
    // THE COPY HERE IS THE REAL COPY, which is the opposite of the choice DesignSystem's own
    // references make. A component must not know a screen's words, so its snapshots pass
    // `Text(verbatim:)`; a screen's words are part of what the screen renders, and a reference that
    // invented its own would stop being a picture of this screen. What stays `verbatim` is the data:
    // an exercise's name is a row in a catalogue, not copy (`G-3.4`).

    @MainActor
    @Suite("Exercise list snapshots")
    struct ExerciseListSnapshotTests {
        @Test func groupedCatalogue() throws {
            try assertSnapshots(named: "ExerciseList-groups") {
                ExerciseGroupList(groups: Fixtures.groups)
            }
        }

        @Test func filterChips() throws {
            try assertSnapshots(named: "ExerciseList-filter-chips") {
                VStack(alignment: .leading, spacing: Spacing.sm.points) {
                    HStack(spacing: Spacing.sm.points) {
                        FilterChip(label: Text(ExerciseLibraryStrings.filterAll), isSelected: false) {}
                        FilterChip(
                            label: Text(ExerciseLibraryStrings.label(for: Movement.squat)),
                            isSelected: true
                        ) {}
                    }
                    FilterChip(
                        label: Text(ExerciseLibraryStrings.recentlyUsedFilter),
                        isSelected: false,
                        isEnabled: false
                    ) {}
                }
            }
        }

        @Test func recencyChipInForce() throws {
            // `FR-1.1.2`'s recency filter once something has been trained inside the window. Its
            // own reference beside the disabled one above, because the two are what the chip looks
            // like in its two lives and the difference between them is exactly what a picture
            // checks — a control that is off and one that cannot be used must not look alike.
            try assertSnapshots(named: "ExerciseList-recency-chip") {
                VStack(alignment: .leading, spacing: Spacing.sm.points) {
                    FilterChip(
                        label: Text(ExerciseLibraryStrings.recentlyUsedFilter),
                        isSelected: false,
                        isEnabled: true
                    ) {}
                    FilterChip(
                        label: Text(ExerciseLibraryStrings.recentlyUsedFilter),
                        isSelected: true,
                        isEnabled: true
                    ) {}
                }
            }
        }

        @Test func archivedChip() throws {
            // Its own reference rather than a line in `filterChips`: this control sits on a row of
            // its own, outside the horizontal scrollers the three facets use, and that placement is
            // the part a picture can check (`FR-1.1.5`, `TR-1.12`).
            try assertSnapshots(named: "ExerciseList-archived-chip") {
                VStack(alignment: .leading, spacing: Spacing.sm.points) {
                    FilterChip(
                        label: Text(ExerciseLibraryStrings.showArchivedFilter),
                        isSelected: false
                    ) {}
                    FilterChip(
                        label: Text(ExerciseLibraryStrings.showArchivedFilter),
                        isSelected: true
                    ) {}
                }
            }
        }

        @Test func emptyCatalogue() throws {
            try assertSnapshots(named: "ExerciseList-empty") {
                EmptyStateView(
                    symbolName: "figure.strengthtraining.traditional",
                    headline: Text(ExerciseLibraryStrings.emptyHeadline),
                    message: Text(ExerciseLibraryStrings.emptyMessage),
                    // The way into the create form, which this state gained once that screen
                    // existed (`FR-1.1.3`). A reference built without it pictures a screen the app
                    // no longer has, and passes while doing so.
                    action: StateAction(Text(ExerciseLibraryStrings.createAction)) {}
                )
            }
        }

        @Test func chooserRows() throws {
            // FR-1.2.2's chooser is this same list with the rows turned into commands. The picture
            // worth keeping is the difference: no chevron, because the tap writes an exercise into
            // the workout and pops rather than opening anything.
            try assertSnapshots(named: "ExerciseList-picker") {
                ExerciseGroupList(groups: Fixtures.groups, select: { _ in })
            }
        }

        @Test func everythingArchivedInTheChooser() throws {
            // No action, unlike the browsing screen's version below: the chooser has no "Show
            // archived" control to offer, FR-1.1.5 being what takes an archived exercise out of the
            // pickers in the first place.
            try assertSnapshots(named: "ExerciseList-picker-archived-only") {
                EmptyStateView(
                    symbolName: "archivebox",
                    headline: Text(ExerciseLibraryStrings.archivedOnlyHeadline),
                    message: Text(ExerciseLibraryStrings.archivedOnlyPickerMessage)
                )
            }
        }

        @Test func archivedRows() throws {
            try assertSnapshots(named: "ExerciseList-archived") {
                ExerciseGroupList(groups: Fixtures.archivedGroups)
            }
        }

        @Test func everythingArchived() throws {
            try assertSnapshots(named: "ExerciseList-archived-only") {
                EmptyStateView(
                    symbolName: "archivebox",
                    headline: Text(ExerciseLibraryStrings.archivedOnlyHeadline),
                    message: Text(ExerciseLibraryStrings.archivedOnlyMessage),
                    action: StateAction(Text(ExerciseLibraryStrings.showArchivedFilter)) {}
                )
            }
        }

        @Test func nothingMatched() throws {
            try assertSnapshots(named: "ExerciseList-no-matches") {
                EmptyStateView(
                    symbolName: "magnifyingglass",
                    headline: Text(ExerciseLibraryStrings.noMatchesHeadline),
                    message: Text(ExerciseLibraryStrings.noMatchesMessage),
                    action: StateAction(Text(ExerciseLibraryStrings.noMatchesAction)) {}
                )
            }
        }

        @Test func readFailed() throws {
            try assertSnapshots(named: "ExerciseList-error") {
                ErrorStateView(
                    headline: Text(ExerciseLibraryStrings.errorHeadline),
                    message: Text(ExerciseLibraryStrings.errorMessage),
                    retry: {}
                )
            }
        }
    }

    /// The catalogue these references render: two movements, and a custom exercise so the badge is
    /// in the picture.
    enum Fixtures {
        static let groups: [ExerciseGroup] = [
            ExerciseGroup(
                movement: .squat,
                exercises: [
                    exercise(id: 1, name: "Back Squat", movement: .squat),
                    exercise(id: 2, name: "Front Squat", movement: .squat, isCustom: true),
                ]
            ),
            ExerciseGroup(
                movement: .bench,
                exercises: [
                    exercise(id: 3, name: "Bench Press", movement: .bench, equipment: .dumbbell)
                ]
            ),
        ]

        /// The list once "show archived" is on (`FR-1.1.5`): a live row and an archived one under
        /// the same heading, which is the only picture that shows the badge doing its job.
        static let archivedGroups: [ExerciseGroup] = [
            ExerciseGroup(
                movement: .squat,
                exercises: [
                    exercise(id: 1, name: "Back Squat", movement: .squat),
                    exercise(id: 4, name: "Smith Machine Squat", movement: .squat, isArchived: true),
                ]
            )
        ]

        /// One exercise, with fixed dates and a fixed identifier so a rendering never moves — and
        /// with `id` a parameter, because `ForEach` keys the rows on it and two rows sharing one is
        /// a rendering that silently loses a row.
        static func exercise(
            id: Int,
            name: String,
            movement: Movement,
            equipment: Equipment = .barbell,
            isCustom: Bool = false,
            isArchived: Bool = false,
            laterality: Laterality = .bilateral,
            barType: BarType = .standard
        ) -> Exercise {
            Exercise(
                id: UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-00000000000\(id)") ?? UUID(),
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0),
                deletedAt: nil,
                name: name,
                movement: movement,
                parentExerciseID: nil,
                equipment: equipment,
                laterality: laterality,
                barType: barType,
                implementCount: 1,
                isCustom: isCustom,
                isArchived: isArchived,
                notes: ""
            )
        }
    }

#endif
