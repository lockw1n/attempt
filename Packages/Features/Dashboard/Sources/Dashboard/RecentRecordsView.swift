import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the feed's five states is current (`FR-1.13.1`, `FR-1.13.3`).
///
/// **Five, and there is no empty and no offline one.** The records are computed from local rows, so
/// there is no fetch to be offline for; and a feed with nothing in it is `FR-1.13.3`'s
/// insufficient-data case rather than an emptied list.
///
/// **The fifth is the one `FR-16.3.4` added, and it is a different sentence rather than a
/// decoration on the fourth.** Under `FR-16.3`'s defaults the feed reports on the dashboard lifts
/// alone and hides baselines, so an empty one no longer means "nothing has produced a record" — it
/// usually means the records are somewhere the configuration excludes, and saying "log a working
/// set" to a lifter who has logged four hundred of them is wrong. What separates the two is
/// whether anything was narrowed at all — the scope, the baseline flag or a chosen scheme list,
/// any one of which can empty the feed on its own — so `nothingYet` is reachable only at the
/// widest setting, where it really is a log with no records in it.
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

    /// It answered, nothing survived a configuration narrower than the widest, and relaxing it is
    /// the offer (`FR-16.3.4`).
    case nothingInScope

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
        guard state.records.isEmpty else { return .ready }
        return state.isNarrowed ? .nothingInScope : .nothingYet
    }
}

/// `FR-1.6.5`'s global feed of recent personal records, across every exercise.
///
/// **A read of the cache and never a recompute** — see
/// ``DerivedValues/PersonalRecordRecomputer/recentRecords(limit:filter:)``, which is where the reason it
/// may not walk the catalogue is written.
///
/// **It subscribes as well as reads** (`TR-1.5`), so a set logged in another tab appears here
/// without the screen being revisited.
struct RecentRecordsFeed: View {
    /// The feed's own state.
    @State private var state: RecentRecordsState

    /// The locale each entry's exercise name is resolved in (`FR-1.14.2`), handed to the state
    /// before its read.
    @Environment(\.locale) private var locale

    /// Builds the feed.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor (`TR-1.6`).
    ///   - catalogue: The exercises, for the name on each entry.
    ///   - settings: The settings row — `FR-16.3`'s configuration and `G-3.1`'s unit.
    ///   - limit: How many entries to draw.
    init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        limit: Int
    ) {
        _state = State(
            initialValue: RecentRecordsState(
                recomputer: records,
                catalogue: catalogue,
                settings: settings,
                limit: limit,
                // FR-16.3.1's default scope is FR-1.9.1's selection, and where the lifter has made
                // none it is this module's rule that says which three lifts those are.
                defaultDashboardExerciseIDs: DashboardDefaults.exerciseIDs(in:)))
    }

    /// Whichever of the five states is current.
    ///
    /// Two tasks, because they have different lifetimes: the first is a read that finishes, the
    /// second runs until the screen goes away.
    var body: some View {
        content
            .task {
                state.nameLanguage = ExerciseNameLanguage(locale)
                await state.load()
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
        case .nothingInScope:
            // FR-16.3.4's offer, and a button rather than a sentence pointing at Settings: the
            // remedy is a setting, so making the reader go and find it is the dead end the
            // requirement is written against.
            InsufficientDataView(
                message: Text(DashboardStrings.recentRecordsNoneInScope),
                action: StateAction(Text(DashboardStrings.recentRecordsShowEverything)) {
                    Task { await state.showEverything() }
                })
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
                    unit: state.displayUnit
                )
            }
        }
    }
}

/// One PR-setting run: the exercise, the scheme, the set behind it, the delta and the day
/// (`FR-1.6.5`, `FR-16.3.3`).
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

    /// What the row says: the exercise, then `FR-16.3.3`'s four — the scheme, the set that produced
    /// it, how far the load moved, and the day.
    private var reading: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            if let exerciseName {
                Text(verbatim: exerciseName)
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                paired
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: TouchTarget.standard.points)
        .contentShape(.rect)
    }

    /// `FR-16.3.3`'s four as two lines: what was lifted and how far it moved, then what record that
    /// is and when.
    ///
    /// **Two lines rather than one, because four readings do not fit on one at the *default* size.**
    /// `ExerciseRecordRow`'s single line carries three and this row carries four; measured at 320
    /// points, the fourth breaks the load from its rep count and the date from its year — a wrap
    /// mid-number, which is the failure `SchemeGrid`'s `.fixedSize` exists to prevent one screen
    /// over. Neither layout priorities nor a `Spacer` fix it: the content is wider than the row.
    ///
    /// **The pairing is what the reader compares.** The delta belongs beside the load it moved, and
    /// the date beside the record it dates; splitting them the other way puts a number next to a
    /// number it says nothing about.
    private var paired: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm.points) {
                loadReading
                movement
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm.points) {
                schemeLabel
                Spacer(minLength: Spacing.sm.points)
                dateReading
            }
        }
    }

    /// The same four stacked, one per line — `NFR-1.10`'s largest sizes, where even a pair is wider
    /// than the row.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            schemeLabel
            loadReading
            movement
            dateReading
        }
    }

    /// What this entry is the record for — `8RM`, `5 × 5`.
    private var schemeLabel: some View {
        Text(label)
            .font(Typography.metricLabel.font)
            .foregroundStyle(ColorToken.textSecondary)
    }

    /// The set or run that produced it.
    private var loadReading: some View {
        Text(sourceGroup)
            .font(Typography.numericValue.font)
            .foregroundStyle(ColorToken.textPrimary)
    }

    /// The day it was set.
    private var dateReading: some View {
        Text(record.achievedAt, format: AppFormat.date(locale: locale))
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textTertiary)
    }

    /// How far the load moved, or the word that stands where it would (`FR-16.3.3`, `FR-16.3.4`).
    ///
    /// **An increase or nothing.** A cell only moves on a strict improvement, so
    /// ``DerivedValues/RecentRecord/delta`` is positive wherever it is not `nil` — the indicator's
    /// other two directions are unreachable here, and the arrow and the sign are what carry that
    /// without colour (`G-4.5`).
    @ViewBuilder private var movement: some View {
        if let delta = record.delta {
            DeltaIndicator(.increase, value: weightStyle.format(delta))
        } else {
            Text(DashboardStrings.recentRecordsBaseline)
                .font(Typography.metricContext.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
    }

    /// What this entry is the record for — see ``RecentRecord/feedLabel``.
    private var label: LocalizedStringResource { record.feedLabel }

    /// The set or run that produced it — see ``RecentRecord/sourceReading(load:reps:sets:)``.
    ///
    /// The numbers are rendered here and the choice between the two readings is not, on ``label``'s
    /// rule: what the row owns is the locale its formatters run in (`G-3.4`).
    private var sourceGroup: LocalizedStringResource {
        record.sourceReading(
            load: weightStyle.format(record.weight),
            reps: record.scheme.reps.formatted(AppFormat.count(locale: locale)),
            sets: record.scheme.sets.formatted(AppFormat.count(locale: locale))
        )
    }

    /// The one weight formatter this row uses, so the load and the delta are rendered alike.
    private var weightStyle: WeightStyle {
        AppFormat.weight(WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale)
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

extension RecentRecord {
    /// What one feed row is the record for — the top N it took at a single set, or the scheme itself
    /// where the run set no rep max at all (`FR-1.6.5`, `FR-16.2.1`).
    ///
    /// **Two cases, where there were three.** The span a set took in one go is not a third label: a
    /// set of eight that beat every N up to eight is an **8RM**, and the seven records below it are
    /// the dominance rule rather than the achievement — see
    /// ``Dashboard/DashboardStrings/recentRecordsRepMax(_:)``, where "1–8-rep max" is retired.
    ///
    /// **The scheme case is not a widening of the rep-max one.** A rep max is a claim about a single
    /// set, and a run whose records all stand at two sets and up — a `100 × 5 × 5` performed after a
    /// heavier set of five — set none; labelling it with an N would name records the lifter's own
    /// history contradicts, at a lighter load than the one that holds them.
    ///
    /// **Off the `View` deliberately.** The choice between the two sentences is the claim worth
    /// testing, and a claim that lives inside a `View` body can only be closed by a picture.
    var feedLabel: LocalizedStringResource {
        guard let reps = repMaxReps else {
            return DashboardStrings.recentRecordsScheme(scheme.reps, scheme.sets)
        }
        return DashboardStrings.recentRecordsRepMax(reps.upperBound)
    }

    /// The set or run that produced it — `145 kg × 8`, `100 kg × 5 × 5` (`FR-16.3.3`).
    ///
    /// **Off the `View` for ``feedLabel``'s reason.** Which of the two readings a row gets is
    /// decided by the record's set count alone, and a claim that lives inside a `View` body can only
    /// be closed by a picture.
    ///
    /// **The record's own scheme, which is the run's shape clamped to the table's bounds.** The
    /// cache stores a cell rather than a performance, so a set taken to twelve reps reads `× 10`
    /// here: what the row states is the record it set, and the twelve-rep set is one tap away on the
    /// exercise's own screen.
    ///
    /// - Parameters:
    ///   - load: The record load, formatted for the row's locale.
    ///   - reps: Its repetitions, likewise.
    ///   - sets: How many consecutive sets, likewise — unused where the record stands at one.
    /// - Returns: The reading.
    func sourceReading(load: String, reps: String, sets: String) -> LocalizedStringResource {
        scheme.sets > 1
            ? DashboardStrings.recentRecordsRun(load, reps, sets)
            : DashboardStrings.recentRecordsSet(load, reps)
    }
}
