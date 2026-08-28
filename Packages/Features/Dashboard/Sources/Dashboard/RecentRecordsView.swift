import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the feed's four states is current (`FR-1.13.1`, `FR-1.13.3`).
///
/// **Four, and there is no empty and no offline one.** The records are computed from local rows, so
/// there is no fetch to be offline for; and a feed with nothing in it is `FR-1.13.3`'s
/// insufficient-data case rather than an emptied list — nothing was filtered away, the sets that
/// would produce a record have not been logged.
///
/// **Nor is there the pair the per-exercise list has.** That screen tells "nothing logged against
/// this exercise" from "logged, but nothing that counts" by counting the exercise's sets; globally
/// the same distinction would be a second read across the whole store to choose between two
/// sentences, so this one says what both have in common.
enum RecentRecordsScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// It answered, and no set this build counts has produced a record.
    case nothingYet

    /// There are records to show.
    case ready

    /// They could not be read; a retry may work.
    case failed

    /// Which state a load is in.
    ///
    /// **The failure outranks a list already on screen**, on `ExerciseRecordsSection`'s rule: a read
    /// that failed leaves the previous answer in `records`, and drawing it under no diagnostic
    /// presents a stale feed as a current one.
    ///
    /// - Parameter state: The feed's load.
    /// - Returns: The state to draw.
    static func current(_ state: RecentRecordsState) -> Self {
        if state.failure != nil { return .failed }
        guard state.hasLoaded else { return .loading }
        return state.records.isEmpty ? .nothingYet : .ready
    }
}

/// `FR-1.6.5`'s global feed of recent personal records, across every exercise.
///
/// **A read of the cache and never a recompute** — see
/// ``DerivedValues/PersonalRecordRecomputer/recentRecords(limit:)``, which is where the reason it
/// may not walk the catalogue is written.
///
/// **It subscribes as well as reads** (`TR-1.5`), so a set logged in another tab appears here
/// without the screen being revisited.
struct RecentRecordsFeed: View {
    /// The feed's own state.
    @State private var state: RecentRecordsState

    /// The unit the loads are shown in (`G-3.1`).
    ///
    /// The screen's own read, and kilograms until it lands — a record reads no setting, which is
    /// what lets `TR-0.3.9` cache it, so the unit is not the state's to carry.
    @State private var unit: MassUnit = .kilograms

    /// Where the display unit comes from.
    private let settings: any SettingsRepository

    /// Builds the feed.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor (`TR-1.6`).
    ///   - catalogue: The exercises, for the name on each entry.
    ///   - settings: The settings row, for the unit the loads are shown in.
    ///   - limit: How many entries to draw.
    init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        limit: Int
    ) {
        self.settings = settings
        _state = State(
            initialValue: RecentRecordsState(
                recomputer: records, catalogue: catalogue, limit: limit))
    }

    /// Whichever of the four states is current.
    ///
    /// Two tasks, because they have different lifetimes: the first is a read that finishes, the
    /// second runs until the screen goes away.
    var body: some View {
        content
            .task {
                await state.load()
                if let stored = try? await settings.settings().displayUnit { unit = stored }
            }
            .task { await state.observeChanges() }
    }

    /// The rows, or the placeholder that stands in for them.
    @ViewBuilder private var content: some View {
        switch RecentRecordsScreenState.current(state) {
        case .loading:
            LoadingStateView()
        case .nothingYet:
            InsufficientDataView(message: Text(DashboardStrings.recentRecordsNone))
        case .failed:
            ErrorStateView(
                message: Text(DashboardStrings.recentRecordsError),
                retry: { Task { await state.load() } }
            )
        case .ready:
            ForEach(state.records, id: \.self) { record in
                RecentRecordRow(
                    record: record,
                    exerciseName: state.exerciseNames[record.exerciseID],
                    unit: unit
                )
            }
        }
    }
}

/// One PR-setting set: the exercise, what it was the record for, the load, and when (`FR-1.6.5`).
///
/// **The whole row links to the exercise's detail, not to the source set** — which is where this
/// row differs from `FR-1.6.2`'s, and it is a decision rather than an omission. Locating a set
/// costs a walk of that exercise's whole history (a set is not readable by its own identifier), and
/// a feed spanning K exercises would pay K of those on the screen the app launches into. The
/// exercise's own detail carries `FR-1.6.2`'s list *with* its source-set links, so the session is
/// one hop further on rather than unreachable — and it is also the screen a reader who does not
/// recognise the movement wants.
///
/// **A `Route` pushed onto whichever stack this is on, not a tab switch**, on `ExerciseRecordRow`'s
/// rule: the destination table is shared across the four tabs, so Back returns to the feed rather
/// than leaving the reader on Train.
///
/// **The exercise's name is optional and the row still renders without it.** A catalogue read is
/// best-effort here (see ``DerivedValues/RecentRecordsState/exerciseNames``), and a record whose
/// exercise will not resolve is still a record.
struct RecentRecordRow: View {
    /// The entry.
    let record: RecentRecord

    /// The exercise's name, where the catalogue answered for it. `verbatim` when drawn: a catalogue
    /// row is data, not copy (`G-3.4`).
    let exerciseName: String?

    /// The unit its load is shown in (`G-3.1`).
    let unit: MassUnit

    /// Which locale the load and the date are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view — `nil` outside the app, where
    /// the unit's own factory step stands.
    @Environment(\.displayPrecision) private var displayPrecision

    /// How large the user reads at — what decides whether the reading is a line or a stack
    /// (`NFR-1.10`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The row, as the link it always is: the exercise is what a cached record names, so unlike
    /// `FR-1.6.2`'s row there is no unresolved form to fall back to.
    var body: some View {
        NavigationLink(
            value: Route.exerciseLibrary(.exerciseDetail(exerciseID: record.exerciseID))
        ) {
            reading
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(DashboardStrings.recentRecordsExerciseHint))
    }

    /// What the row says: the exercise, then what it is the record for, the load and the day.
    private var reading: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            if let exerciseName {
                Text(verbatim: exerciseName)
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            layout {
                Text(label)
                    .font(Typography.metricLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
                Spacer(minLength: Spacing.sm.points)
                Text(
                    record.weight,
                    format: AppFormat.weight(
                        WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale)
                )
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
                Text(record.achievedAt, format: AppFormat.date(locale: locale))
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: TouchTarget.standard.points)
        .contentShape(.rect)
    }

    /// What this entry is the record for — one N, or the span a single set took in one go.
    private var label: LocalizedStringResource {
        record.reps.lowerBound == record.reps.upperBound
            ? DashboardStrings.recentRecordsRepMax(record.reps.lowerBound)
            : DashboardStrings.recentRecordsRepMaxRange(
                record.reps.lowerBound, record.reps.upperBound)
    }

    /// The line, or the stack — `ExerciseRecordRow`'s measured switch, for its reason: at
    /// `accessibility3` a date pushed to the trailing edge takes the width the load needs.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs.points))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm.points))
    }
}

/// The full recent-PR list, behind the dashboard's card (`FR-1.6.5`, `DashboardRoute`).
///
/// The `ScrollView`/`VStack` shape every screen in this app uses rather than a `List`, for
/// `TR-1.12`'s reason: the snapshot harness renders through `ImageRenderer`, which draws a
/// placeholder for anything UIKit-backed.
public struct RecentRecordsView: View {
    /// The app's one recompute actor (`TR-1.6`).
    private let records: PersonalRecordRecomputer

    /// The exercises, for the name on each entry.
    private let catalogue: any ExerciseRepository

    /// The settings row, for the unit the loads are shown in.
    private let settings: any SettingsRepository

    /// Builds the screen.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor, so a set logged anywhere reaches this.
    ///   - catalogue: Where the exercise names come from.
    ///   - settings: The settings row, for the unit (`G-3.1`).
    public init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        self.records = records
        self.catalogue = catalogue
        self.settings = settings
    }

    /// The feed at its list length.
    ///
    /// **A bare `Card` rather than a `GroupedSection`**, which is the one place the two shapes
    /// differ: the navigation bar already carries the title, and a heading repeating it directly
    /// underneath reads as a second, narrower section. The card *is* the heading here.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.lg.points) {
                        RecentRecordsFeed(
                            records: records,
                            catalogue: catalogue,
                            settings: settings,
                            limit: RecentRecordsState.listLimit
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(DashboardStrings.recentRecordsTitle))
    }
}

/// The dashboard's own recent-PR card (`FR-1.9.3`), and the whole of what `T-1.56` has to place.
///
/// **The card and the screen are one feed at two lengths**, which is why they share a title, a row
/// and a state machine — the only differences are how many entries are drawn and the control that
/// opens the rest.
public struct RecentRecordsSection: View {
    /// The app's one recompute actor (`TR-1.6`).
    private let records: PersonalRecordRecomputer

    /// The exercises, for the name on each entry.
    private let catalogue: any ExerciseRepository

    /// The settings row, for the unit the loads are shown in.
    private let settings: any SettingsRepository

    /// Builds the card.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor.
    ///   - catalogue: Where the exercise names come from.
    ///   - settings: The settings row, for the unit (`G-3.1`).
    public init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        self.records = records
        self.catalogue = catalogue
        self.settings = settings
    }

    /// The five most recent entries, then the way to the rest of them.
    public var body: some View {
        GroupedSection(Text(DashboardStrings.recentRecordsTitle)) {
            RecentRecordsFeed(
                records: records,
                catalogue: catalogue,
                settings: settings,
                limit: RecentRecordsState.cardLimit
            )
            NavigationLink(value: Route.dashboard(.recentPersonalRecords)) {
                Text(DashboardStrings.recentRecordsSeeAll)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.brandAccent)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}
