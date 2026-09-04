import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the table's four states is current (`FR-1.13.1`, `FR-1.13.3`).
///
/// **Four, where ``ExerciseRecordsScreenState`` has five.** That one tells "nothing logged against
/// this exercise" from "logged, but nothing that counts" using a set count the detail screen has
/// already read; this screen is reached by a route carrying an identifier and nothing else, and a
/// second read of the whole history to choose between two sentences is a walk for a sentence. The
/// one it says instead is the rule — see ``ExerciseLibraryStrings/recordsNoWorkingSets``, which is
/// true of both cases.
enum ExerciseRecordsTableState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// It answered, and no run this build counts has produced a record.
    case nothingYet

    /// There are cells to show.
    case ready

    /// They could not be read; a retry may work.
    case failed

    /// Which state a load is in.
    ///
    /// The failure outranks a table already on screen, on ``ExerciseRecordsScreenState/current(_:hasLoggedSets:)``'s
    /// rule and for its reason.
    ///
    /// - Parameter state: The records' load.
    /// - Returns: The state to draw.
    static func current(_ state: ExerciseRecordsState) -> Self {
        if state.recordsFailure != nil { return .failed }
        guard state.hasLoaded else { return .loading }
        return state.schemeRecords.isEmpty ? .nothingYet : .ready
    }
}

/// `FR-16.2.4`'s whole table for one exercise: rep counts down, set counts across.
///
/// **A screen rather than a section**, for the reason ``AppNavigation/ExerciseLibraryRoute/exerciseRecords(exerciseID:)``
/// gives. It reads for itself and subscribes for itself (`TR-1.5`), on ``ExerciseRecordsSection``'s
/// terms — the two are the same read at two extents, so a set logged in another tab moves both.
public struct ExerciseRecordsTableView: View {
    /// The records' own state.
    @State private var state: ExerciseRecordsState

    /// The unit the loads are shown in (`G-3.1`).
    ///
    /// The screen's own read, and kilograms until it lands — ``ExerciseRecordsSection/unit``'s rule.
    @State private var unit: MassUnit = .kilograms

    /// Where the display unit comes from.
    private let settings: any SettingsRepository

    /// Builds the table over the exercise it reports on.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise's records to show.
    ///   - records: The app's one recompute actor (`TR-1.6`), so a set logged anywhere reaches this.
    ///   - settings: The settings row, for the unit the loads are shown in.
    public init(
        exerciseID: UUID,
        records: PersonalRecordRecomputer,
        settings: any SettingsRepository
    ) {
        self.settings = settings
        _state = State(initialValue: ExerciseRecordsState(exerciseID: exerciseID, recomputer: records))
    }

    /// Whichever of the four states is current, under the screen's own title.
    ///
    /// The `ScrollView`/`VStack` shape every screen here uses rather than a `List`, for `TR-1.12`'s
    /// reason.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.lg.points) {
                        content
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(ExerciseLibraryStrings.recordsTableTitle))
        .task {
            await reload()
            if let stored = try? await settings.settings().displayUnit { unit = stored }
        }
        .task { await state.observeChanges(includingEstimate: false) }
    }

    /// The grid, or the placeholder that stands in for it.
    @ViewBuilder private var content: some View {
        switch ExerciseRecordsTableState.current(state) {
        case .loading:
            LoadingStateView()
        case .nothingYet:
            InsufficientDataView(message: Text(ExerciseLibraryStrings.recordsNoWorkingSets))
        case .failed:
            ErrorStateView(
                message: Text(ExerciseLibraryStrings.recordsError),
                retry: { Task { await reload() } }
            )
        case .ready:
            SchemeTableGrid(
                table: ExerciseSchemeTable(state.schemeRecords),
                unit: unit,
                sessions: state.sourceSessions
            )
        }
    }

    /// The cached numbers, then the links they resolve to — ``ExerciseRecordsSection/reload()``'s
    /// pair, and not ``DerivedValues/ExerciseRecordsState/load()``, which also walks for an estimate
    /// this screen never draws.
    private func reload() async {
        await state.loadRecords()
        await state.loadSources()
    }
}

/// `FR-16.2.4`'s table, in the container that lets it be wider than the screen.
///
/// **It scrolls horizontally**, which is what keeps `NFR-1.10`'s largest type from squeezing six
/// columns into a phone's width — the vertical scroll belongs to the screen and this one to the
/// grid, so a reader at `accessibility3` moves across the table without moving the page.
///
/// **The wrapper is one line and the grid is a view of its own for `TR-1.12`'s reason**: a
/// `ScrollView` is UIKit-backed, so a reference taken through one is the renderer's placeholder —
/// measured here, as a recorded image with nothing in it. ``SchemeGrid`` is what the snapshot
/// pictures.
struct SchemeTableGrid: View {
    /// The records, laid out.
    let table: ExerciseSchemeTable

    /// The unit the loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// The session each record's source set was performed in, keyed on the set — `FR-1.6.2`'s link,
    /// which `FR-16.2.4` inherits by making the record list a table.
    let sessions: [UUID: UUID]

    /// The grid, in its own scroller.
    var body: some View {
        ScrollView(.horizontal) {
            SchemeGrid(table: table, unit: unit, sessions: sessions)
        }
    }
}

/// The cells themselves: a heading row of set counts, then one row per rep count (`FR-16.2.4`).
struct SchemeGrid: View {
    /// The records, laid out.
    let table: ExerciseSchemeTable

    /// The unit the loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// The session each record's source set was performed in, keyed on the set.
    let sessions: [UUID: UUID]

    /// Which locale the row headings' numerals are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The grid, headings included.
    var body: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: Spacing.md.points,
            verticalSpacing: Spacing.sm.points
        ) {
            GridRow {
                Text(ExerciseLibraryStrings.recordsRepsHeader)
                    .font(Typography.metricLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
                ForEach(table.setCounts, id: \.self) { sets in
                    Text(ExerciseLibraryStrings.recordsSetColumn(sets))
                        .font(Typography.metricLabel.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
            }
            ForEach(table.repCounts, id: \.self) { reps in
                GridRow {
                    Text(reps, format: AppFormat.count(locale: locale))
                        .font(Typography.metricLabel.font)
                        .foregroundStyle(ColorToken.textSecondary)
                    ForEach(table.setCounts, id: \.self) { sets in
                        cell(reps: reps, sets: sets)
                    }
                }
            }
        }
        .padding(.trailing, Spacing.sm.points)
        // The columns keep their own width and the scroller carries the overflow. Without this the
        // grid is squeezed into whatever it is offered and `132.5 kg` breaks across two lines —
        // which is `SetGroupRow`'s measured finding, met again one dimension over.
        .fixedSize(horizontal: true, vertical: false)
    }

    /// One cell — the record, or the blank that says the scheme was never performed.
    ///
    /// - Parameters:
    ///   - reps: The row.
    ///   - sets: The column.
    /// - Returns: The cell.
    @ViewBuilder private func cell(reps: Int, sets: Int) -> some View {
        let scheme = RecordScheme(reps: reps, sets: sets)
        if let record = table.record(at: scheme) {
            SchemeRecordCell(
                record: record,
                unit: unit,
                sessionID: sessions[record.record.sourceSetID]
            )
        } else {
            // Blank, not zero: `Weight` is signed, so a zero here would be a load the lifter lifted.
            //
            // A placeholder rather than nothing at all: `Grid` fills a row's cells in order, so a
            // row that skipped one would put every cell after it under the wrong column heading. It
            // is sized to the smallest token so it never widens the column it stands in.
            Color.clear
                .frame(width: Spacing.xxs.points, height: Spacing.xxs.points)
                .accessibilityHidden(true)
        }
    }
}

/// One cell of the table: the load, the day, and the way to the session behind it (`FR-16.2.4`).
///
/// **The whole cell is the link, and only where the source set resolved** — ``ExerciseRecordRow``'s
/// rule, which this inherits along with the record list it is a two-dimensional form of.
///
/// **Its VoiceOver label names the scheme, which nothing in the cell draws.** A reader moving across
/// a grid does not carry the row and column headings with them, so combining the children would
/// announce a load and a date belonging to nothing — see
/// ``ExerciseLibraryStrings/recordsCellLabel(reps:sets:load:date:)``.
struct SchemeRecordCell: View {
    /// The record and the cell it stands at.
    let record: DatedSchemeRecord

    /// The unit its load is shown in (`G-3.1`).
    let unit: MassUnit

    /// The session the source set was performed in, where it resolved.
    let sessionID: UUID?

    /// Which locale the load and the date are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    /// The cell, as a link where there is one to make.
    @ViewBuilder var body: some View {
        if let sessionID {
            NavigationLink(value: Route.history(.session(sessionID: sessionID))) {
                reading
            }
            .buttonStyle(.plain)
            .accessibilityElement()
            .accessibilityLabel(Text(label))
            .accessibilityHint(Text(ExerciseLibraryStrings.recordsSourceHint))
        } else {
            reading
                .accessibilityElement()
                .accessibilityLabel(Text(label))
        }
    }

    /// What the cell shows: the load, and the day it was set beneath it.
    private var reading: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            Text(verbatim: renderedLoad)
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
            Text(verbatim: renderedDate)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textTertiary)
        }
        .frame(minHeight: TouchTarget.standard.points, alignment: .leading)
        .contentShape(.rect)
    }

    /// The whole cell as VoiceOver reads it (`G-4.2`).
    private var label: LocalizedStringResource {
        ExerciseLibraryStrings.recordsCellLabel(
            reps: record.scheme.reps,
            sets: record.scheme.sets,
            load: renderedLoad,
            date: renderedDate
        )
    }

    /// The load, formatted once — the drawn text and the spoken label are the same number.
    private var renderedLoad: String {
        AppFormat.weight(WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale)
            .format(record.record.weight)
    }

    /// The day, likewise.
    private var renderedDate: String {
        AppFormat.date(locale: locale).format(record.record.achievedAt)
    }
}

/// One scheme record as the detail section's diagonal draws it — `5 × 5`, the load, the day.
///
/// **``ExerciseRecordRow`` with a two-dimensional heading**, and a second view rather than a
/// parameter on that one: the two differ only in what heads them, and that heading is the whole
/// distinction between `FR-1.6.1`'s rep max and `FR-16.2.1`'s scheme. Everything else — the link,
/// the layout switch at `NFR-1.10`'s sizes, the reason the `Spacer` sits inside it — is that row's,
/// for that row's reasons.
struct ExerciseSchemeRow: View {
    /// The record and the cell it stands at.
    let record: DatedSchemeRecord

    /// The unit its load is shown in (`G-3.1`).
    let unit: MassUnit

    /// The session the source set was performed in, where it resolved.
    let sessionID: UUID?

    /// Which locale the load and the date are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    /// How large the user reads at (`NFR-1.10`).
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

    /// What the row says: the scheme, then the load and the day it was set.
    private var reading: some View {
        layout {
            Text(ExerciseLibraryStrings.recordsScheme(record.scheme.reps, record.scheme.sets))
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            Spacer(minLength: Spacing.sm.points)
            Text(
                record.record.weight,
                format: AppFormat.weight(
                    WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale)
            )
            .font(Typography.numericValue.font)
            .foregroundStyle(ColorToken.textPrimary)
            Text(record.record.achievedAt, format: AppFormat.date(locale: locale))
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: TouchTarget.standard.points)
        .contentShape(.rect)
    }

    /// The line, or the stack — ``ExerciseRecordRow/layout``'s measured switch, for its reason.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs.points))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm.points))
    }
}
