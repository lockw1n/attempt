import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// `FR-1.6.2`'s split of the ten N-rep maxes: the five a lifter reads at a glance, and the five
/// behind a disclosure.
///
/// **A value rather than two filters on the view**, so "which N are prominent" can be asserted
/// without rendering anything and has exactly one home. The requirement names the boundary — 1–5RM
/// prominently, 6–10RM behind a disclosure — and this is where that sentence is code.
///
/// **An N no set reached is absent from both halves, not present at zero.** `Weight` is signed, so
/// zero is a real load; the list a lifter sees is the records they hold, not ten rows of which some
/// are blank.
struct ExerciseRecordList: Equatable {
    /// The N's shown without asking — `FR-1.6.2`'s "displayed prominently".
    static let prominentReps = 1...5

    /// The 1–5RM this exercise holds, ascending.
    let prominent: [DatedRepMax]

    /// The 6–10RM it holds, ascending, drawn only once the disclosure is open.
    let disclosed: [DatedRepMax]

    /// Splits one exercise's records.
    ///
    /// - Parameter repMaxes: What the recompute produced, in any order.
    init(_ repMaxes: [DatedRepMax]) {
        let ordered = repMaxes.sorted { $0.reps < $1.reps }
        prominent = ordered.filter { Self.prominentReps.contains($0.reps) }
        disclosed = ordered.filter { !Self.prominentReps.contains($0.reps) }
    }

    /// Whether this exercise holds no records at all.
    var isEmpty: Bool { prominent.isEmpty && disclosed.isEmpty }
}

/// Which of the section's five states is current (`FR-1.13.1`, `FR-1.13.3`).
///
/// **Five, and two of them are "nothing to show".** An exercise nothing has ever been logged against
/// and one whose every set is a warmup are told apart by the *sets*, not by the records — both hold
/// no records, and the sentence each is owed is different. See ``ExerciseLibraryStrings/recordsNone``.
///
/// No empty and no offline state: the records are computed from local rows, so there is no fetch to
/// be offline for, and "this exercise holds none" is `FR-1.13.3`'s insufficient-data case rather than
/// an emptied list.
enum ExerciseRecordsScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// It answered, and nothing has ever been logged against this exercise.
    case noneYet

    /// Sets have been logged, and none of them is one `FR-1.6.1` counts.
    case noRecordsYet

    /// There are records to show.
    case ready

    /// They could not be read; a retry may work.
    case failed

    /// Which state a load is in.
    ///
    /// **The failure outranks everything, including a list already on screen.** A record read that
    /// fails leaves ``DerivedValues/ExerciseRecordsState/repMaxes`` holding the last answer, and
    /// drawing it under no diagnostic would present a stale list as a current one — which is the
    /// distinction `FR-1.13.1` exists to keep.
    ///
    /// **The *list's* failure, not the merged one.** The two halves read different stores — the
    /// records answer from `G-1.5`'s cache and the estimate walks the history — so a workout store
    /// that refuses fails the estimate while the cache answers this section perfectly well. Read
    /// merged, that drew an error over a list nothing was wrong with, which names the wrong thing as
    /// broken; this section draws no estimate and does not speak for one.
    ///
    /// - Parameters:
    ///   - state: The records' load.
    ///   - hasLoggedSets: Whether any set at all has been logged against this exercise.
    /// - Returns: The state to draw.
    static func current(_ state: ExerciseRecordsState, hasLoggedSets: Bool) -> Self {
        if state.recordsFailure != nil { return .failed }
        guard state.hasLoaded else { return .loading }
        if !state.repMaxes.isEmpty { return .ready }
        return hasLoggedSets ? .noRecordsYet : .noneYet
    }
}

/// This exercise's personal records (`FR-1.6.2`).
///
/// **A section with a read of its own**, on ``ExerciseHistorySection``'s rule and for its reason: a
/// derived value that cannot be computed must not cost the reader `FR-1.1.6`'s movement, equipment
/// and notes.
///
/// **It subscribes as well as reads** (`TR-1.5`). A set logged in another tab moves a record on this
/// screen, and the alternative to a subscription is polling on every appearance — which is the
/// walk `G-1.5`'s cache exists to avoid paying.
struct ExerciseRecordsSection: View {
    @State private var state: ExerciseRecordsState

    /// The unit the loads are shown in (`G-3.1`).
    ///
    /// **The screen's own read, and kilograms until it lands.** The records themselves read no
    /// setting — which is exactly why `TR-0.3.9` may cache them — so the unit is not
    /// ``DerivedValues/ExerciseRecordsState``'s to carry; it is one stored property and one read, on
    /// `ActiveSessionStore`'s rule that a load with no unit on it is worse than one showing the
    /// majority default.
    @State private var unit: MassUnit = .kilograms

    /// Whether `FR-1.6.2`'s 6–10RM are revealed.
    ///
    /// **Closed on every appearance, and stored nowhere.** The disclosure is a reading position
    /// rather than a preference (`NFR-1.8` covers logged data), and the requirement's own shape says
    /// the five that matter are the ones on screen when the section opens.
    @State private var showsHigherReps = false

    /// Whether any set at all has been logged against it, which decides which of the two
    /// nothing-to-show sentences applies.
    private let hasLoggedSets: Bool

    /// Where the display unit comes from.
    private let settings: any SettingsRepository

    /// Builds the section over the exercise it reports on.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise's records to show.
    ///   - hasLoggedSets: Whether anything has been logged against it — see ``hasLoggedSets``.
    ///   - records: The app's one recompute actor (`TR-1.6`), so a set logged anywhere reaches this.
    ///   - settings: The settings row, for the unit the loads are shown in.
    init(
        exerciseID: UUID,
        hasLoggedSets: Bool,
        records: PersonalRecordRecomputer,
        settings: any SettingsRepository
    ) {
        self.hasLoggedSets = hasLoggedSets
        self.settings = settings
        _state = State(initialValue: ExerciseRecordsState(exerciseID: exerciseID, recomputer: records))
    }

    /// The heading, then whichever of the section's five states is current.
    ///
    /// **Two tasks, because they have different lifetimes.** The first is a read that finishes; the
    /// second runs until the screen goes away, which is what `TR-1.5`'s subscription is.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.recordsSection)) {
            switch ExerciseRecordsScreenState.current(state, hasLoggedSets: hasLoggedSets) {
            case .loading:
                LoadingStateView()
            case .noneYet:
                InsufficientDataView(message: Text(ExerciseLibraryStrings.recordsNone))
            case .noRecordsYet:
                InsufficientDataView(message: Text(ExerciseLibraryStrings.recordsNoWorkingSets))
            case .failed:
                ErrorStateView(
                    message: Text(ExerciseLibraryStrings.recordsError),
                    retry: { Task { await reload() } }
                )
            case .ready:
                records
            }
        }
        .task {
            await reload()
            if let stored = try? await settings.settings().displayUnit { unit = stored }
        }
        .task { await state.observeChanges(includingEstimate: false) }
    }

    /// This section's own read: `G-1.5`'s cached numbers, then the links they resolve to.
    ///
    /// **Not ``DerivedValues/ExerciseRecordsState/load()``**, which also walks the whole history for
    /// `FR-1.7.1`'s estimate — a number drawn in the section below this one and never in this one.
    private func reload() async {
        await state.loadRecords()
        await state.loadSources()
    }

    /// The 1–5RM, then the control that reveals the rest.
    ///
    /// The disclosure is drawn only when there is something behind it: a control promising rows the
    /// exercise does not hold is the failure a bare "Show more" has.
    @ViewBuilder private var records: some View {
        let list = ExerciseRecordList(state.repMaxes)
        ForEach(list.prominent, id: \.reps) { row(for: $0) }
        if !list.disclosed.isEmpty {
            RecordDisclosureHeader(isExpanded: showsHigherReps) { showsHigherReps.toggle() }
            if showsHigherReps {
                ForEach(list.disclosed, id: \.reps) { row(for: $0) }
            }
        }
    }

    /// One record's row, linked to its source set where that resolved.
    ///
    /// - Parameter repMax: The record and the N it stands at.
    /// - Returns: The row.
    private func row(for repMax: DatedRepMax) -> some View {
        ExerciseRecordRow(
            repMax: repMax,
            unit: unit,
            sessionID: state.sourceSessions[repMax.record.sourceSetID]
        )
    }
}

/// `FR-1.6.2`'s disclosure over the 6–10RM.
///
/// **A button of its own rather than a `DisclosureGroup`**, on ``WarmupSectionHeader``'s shape: the
/// whole line is the target rather than a chevron, and the fold is announced as a *value* because
/// there is no expanded trait and `.isSelected` means a chosen filter everywhere else in this app.
struct RecordDisclosureHeader: View {
    /// Whether the higher rep maxes are revealed.
    let isExpanded: Bool

    /// Reveals them, or folds them away.
    let toggle: () -> Void

    /// The label and its chevron, as one control across the section's width.
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.sm.points) {
                Text(ExerciseLibraryStrings.recordsMore)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .multilineTextAlignment(.leading)
                    // Wraps rather than truncates: measured at `accessibility3`, the label came out
                    // as "6–10-rep m…", which is a control whose name has been cut in half. The
                    // chevron keeps its width and the words take a second line.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm.points)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            Text(
                isExpanded
                    ? ExerciseLibraryStrings.recordsMoreExpanded
                    : ExerciseLibraryStrings.recordsMoreCollapsed
            )
        )
    }
}

/// One N-rep max: what it is the record for, what was lifted, and when (`FR-1.6.2`).
///
/// **The whole row is the link, and only where the source set resolved.** `FR-1.6.2` asks for a link
/// to the source set and the session is the screen that shows one; a row whose set could not be
/// located is drawn as what it is — a record — rather than as a control that would navigate nowhere.
///
/// **A `Route.history` pushed onto whichever stack this screen is on, not a tab switch.** The
/// destination table is shared across the four tabs, which is what one `Route` enum buys; taking
/// `NavigationState.navigate(to:)` instead would move the user to History and leave the exercise
/// behind on Train, so Back would not return them to the record they tapped.
struct ExerciseRecordRow: View {
    /// The record and the N it stands at.
    let repMax: DatedRepMax

    /// The unit its load is shown in (`G-3.1`).
    let unit: MassUnit

    /// The session the source set was performed in, where it resolved.
    let sessionID: UUID?

    /// Which locale the load and the date are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// How large the user reads at — what decides whether this row is a line or a stack
    /// (`NFR-1.10`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The row, as a link where there is one to make.
    @ViewBuilder var body: some View {
        if let sessionID {
            NavigationLink(value: Route.history(.session(sessionID: sessionID))) {
                reading
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(ExerciseLibraryStrings.recordsSourceHint))
        } else {
            reading
                .accessibilityElement(children: .combine)
        }
    }

    /// What the row says: the N, then the load and the day it was set.
    ///
    /// A line at ordinary sizes and a stack at `NFR-1.10`'s, on ``ExerciseHistoryRow``'s measured
    /// switch and for its reason — at `accessibility3` a date pushed to the trailing edge takes the
    /// width `102.5 kg` needs and the load breaks mid-number.
    private var reading: some View {
        layout {
            Text(ExerciseLibraryStrings.recordsRepMax(repMax.reps))
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            Spacer(minLength: Spacing.sm.points)
            Text(repMax.record.weight, format: AppFormat.weight(in: unit, locale: locale))
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
            Text(repMax.record.achievedAt, format: AppFormat.date(locale: locale))
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: TouchTarget.standard.points)
        .contentShape(.rect)
    }

    /// The line, or the stack. One `AnyLayout` rather than two branches of the body, so the row keeps
    /// its identity — and with it its accessibility element — across the switch.
    ///
    /// **The `Spacer` is inside the switching layout deliberately.** In the row it pushes the load
    /// and the date to the trailing edge; stacked it collapses to the minimum length, which is a gap
    /// between the heading and the value rather than a blank line.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs.points))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm.points))
    }
}
