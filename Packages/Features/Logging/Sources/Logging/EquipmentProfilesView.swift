import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Every gym the user has set up, and the way to add, switch or edit one (`FR-1.4.2`, `FR-1.4.3`,
/// `FR-1.10.3`).
///
/// **One screen for both entry points**, and it lives in this module rather than in `Settings`
/// because the plate calculator is the other one: `TR-1.3` keeps the two feature packages from
/// depending on each other, so the screen belongs to the module that already owns the equipment —
/// and the app target composes it under Settings' own route, exactly as it composes the exercise
/// picker onto the Train tab.
///
/// **It is built over ``PlateCalculatorStore`` rather than over a repository**, which is what keeps
/// a switch made here from needing a second read path: the store is where the calculator's answer to
/// *which gym is this* lives, so every write on this screen ends with that store re-reading it.
public struct EquipmentProfilesView: View {
    /// The store the calculator loads against, and this screen's way to both repositories.
    private let store: PlateCalculatorStore

    /// The list, and the operations on it.
    @State private var state: EquipmentProfilesState

    /// The profile the editor is open over, or `nil` when it is closed.
    ///
    /// **The editor is presented rather than pushed, and carries no `Route`** — the set editor's
    /// rule, one screen along: a form holding an unsaved draft is not a place in the app, and a
    /// restored stack that reopened it would present an empty form claiming to be an edit of a row
    /// nothing had read.
    @State private var editing: EquipmentEditorTarget?

    /// Builds the screen over the store the calculator reads.
    ///
    /// - Parameter store: The equipment store — where the profiles are read and written, and what
    ///   re-reads once one of them changes.
    public init(store: PlateCalculatorStore) {
        self.store = store
        _state = State(initialValue: EquipmentProfilesState(repository: store.repository))
    }

    /// The list in whichever of `FR-1.13.1`'s states the read left it, with the editor over it.
    public var body: some View {
        ScrollView {
            EquipmentProfilesContent(
                state: EquipmentProfilesScreenState.current(state.phase),
                profiles: state.profiles,
                activeProfileID: state.activeProfileID,
                unit: store.displayUnit,
                writeFailure: state.writeFailure,
                add: {
                    state.clearWriteFailure()
                    editing = .create
                },
                edit: {
                    state.clearWriteFailure()
                    editing = .edit($0)
                },
                use: { profileID in perform { await state.makeActive(profileID) } },
                retry: { perform { await state.load() } }
            )
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(LoggingStrings.equipmentTitle))
        .task {
            await state.load()
            await store.load()
        }
        .sheet(item: $editing) { target in
            EquipmentProfileEditorSheet(
                profile: target.profile,
                unit: store.displayUnit,
                writeFailure: state.writeFailure,
                save: { draft in
                    let saved = await state.save(draft, replacing: target.profile)
                    if saved {
                        await store.load()
                        editing = nil
                    }
                },
                delete: {
                    if let profile = target.profile {
                        await state.delete(profile.id)
                        await store.load()
                    }
                    editing = nil
                },
                cancel: { editing = nil }
            )
        }
    }

    /// Runs one operation, then lets the calculator's store see what it did.
    ///
    /// - Parameter operation: The write, or the read that retries a failed one.
    private func perform(_ operation: @escaping () async -> Void) {
        Task {
            await operation()
            await store.load()
        }
    }
}

/// Which profile the editor is open over.
///
/// **A case for a new profile rather than an optional identifier**, on `ExerciseLibraryRoute`'s
/// rule: an optional payload makes one value mean two screens, one that edits a row and one that
/// cannot.
enum EquipmentEditorTarget: Identifiable {
    /// A gym being added (`FR-1.4.2`).
    case create

    /// A gym being edited.
    case edit(EquipmentProfile)

    /// What the presentation is keyed on. The create case answers with a fixed identity, so opening
    /// the form twice does not re-present it.
    var id: UUID {
        switch self {
        case .create: UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
        case .edit(let profile): profile.id
        }
    }

    /// The row being edited, or `nil` while one is being added.
    var profile: EquipmentProfile? {
        switch self {
        case .create: nil
        case .edit(let profile): profile
        }
    }
}

/// What the equipment screen draws, without the scroll view or the sheet around it.
///
/// A type of its own for ``PlateCalculatorContent``'s reason (`TR-1.12`): `ImageRenderer` lays a
/// `ScrollView`'s content out and draws none of it, so a reference taken over the screen above would
/// be a picture of a navigation bar. It takes values rather than the state, so a reference renders
/// without a repository behind it.
struct EquipmentProfilesContent: View {
    /// Which of `FR-1.13.1`'s states the screen is in.
    let state: EquipmentProfilesScreenState

    /// The gyms, in name order.
    let profiles: [EquipmentProfile]

    /// Which one every loading is worked out against, or `nil` when none is.
    let activeProfileID: UUID?

    /// The unit weights are drawn in (`G-3.1`).
    let unit: MassUnit

    /// The last write that failed, as a diagnostic (`G-3.4`), or `nil`.
    let writeFailure: String?

    /// Opens the editor over a new gym.
    let add: () -> Void

    /// Opens the editor over an existing one.
    let edit: (EquipmentProfile) -> Void

    /// Switches to a gym (`FR-1.4.3`).
    let use: (UUID) -> Void

    /// Reads the list again — offered on the one failure a second read could resolve.
    let retry: () -> Void

    /// Which locale the weights are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The failed write, if there was one, then whichever state the read left the screen in.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            // Above the list rather than in place of it, on `SettingsLandingView`'s rule: the rows
            // are still there and still editable, so replacing them with the error would take away
            // the retry, which is the next tap.
            if let writeFailure {
                DiagnosticCard(
                    title: Text(LoggingStrings.equipmentWriteErrorTitle), detail: writeFailure)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The screen's four states (`FR-1.13.1`), each one of the shared components.
    ///
    /// **No offline state**: a profile is a local row (`G-2.1`, `G-2.3`), so a connection has
    /// nothing to do with whether this screen can answer. **No insufficient-data state**: nothing
    /// here is derived — a gym is what the user typed in.
    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            LoadingStateView()
        case .empty:
            EmptyStateView(
                symbolName: "dumbbell",
                headline: Text(LoggingStrings.equipmentEmptyHeadline),
                message: Text(LoggingStrings.equipmentEmptyMessage),
                action: StateAction(Text(LoggingStrings.equipmentAddAction), handler: add)
            )
        case .failed:
            ErrorStateView(
                headline: Text(LoggingStrings.equipmentErrorHeadline),
                message: Text(LoggingStrings.equipmentErrorMessage),
                retry: retry
            )
        case .ready:
            list
        }
    }

    /// The gyms, then the command that adds another.
    ///
    /// **A line above them when none is in use**, which is the state deleting the active gym leaves
    /// behind: the repository promotes nothing, deliberately, so every row here offers *Use this
    /// gym* and not one carries the badge. Read off the badges alone that is an absence the user has
    /// to notice; the calculator says it outright, and this is the screen that can act on it.
    private var list: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            if activeProfileID == nil {
                Card {
                    Text(LoggingStrings.equipmentNoneActive)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(profiles, id: \.id) { profile in
                row(profile)
            }
            Button(action: add) { Text(LoggingStrings.equipmentAddAction) }
                .buttonStyle(.primaryAction(.fill))
        }
    }

    /// One gym: what it is, whether it is the one in use, and the two things to do with it.
    ///
    /// - Parameter profile: The gym.
    /// - Returns: The row.
    private func row(_ profile: EquipmentProfile) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                HStack(spacing: Spacing.sm.points) {
                    Text(verbatim: EquipmentProfileSummary.name(of: profile))
                        .font(Typography.cardTitle.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Spacer(minLength: Spacing.sm.points)
                    if profile.id == activeProfileID {
                        activeBadge
                    }
                }
                Text(EquipmentProfileSummary.bar(of: profile, unit: unit, locale: locale))
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                Text(
                    verbatim: EquipmentProfileSummary.plates(
                        of: profile, unit: unit, locale: locale)
                )
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                commands(profile)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The two commands on a row: switch to this gym, and open it.
    ///
    /// **The switch is absent on the gym already in use rather than disabled**, because the badge
    /// beside the name already says why it would do nothing.
    ///
    /// - Parameter profile: The gym.
    /// - Returns: The commands.
    private func commands(_ profile: EquipmentProfile) -> some View {
        HStack(spacing: Spacing.md.points) {
            if profile.id != activeProfileID {
                Button {
                    use(profile.id)
                } label: {
                    Text(LoggingStrings.equipmentUseAction)
                        .font(Typography.actionLabel.font)
                        .foregroundStyle(ColorToken.brandAccent)
                        .frame(minHeight: TouchTarget.logging.points)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: Spacing.sm.points)
            Button {
                edit(profile)
            } label: {
                Text(LoggingStrings.equipmentEditAction)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .frame(minHeight: TouchTarget.logging.points)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// The badge on the gym every loading is worked out against.
    ///
    /// **A word and not a tint** (`G-4.5`): which gym is in use must not be carried by colour alone.
    private var activeBadge: some View {
        Text(LoggingStrings.equipmentActiveBadge)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.brandAccent)
            .padding(.horizontal, Spacing.sm.points)
            .padding(.vertical, Spacing.xxs.points)
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points))
    }
}

/// A failure shown as what it is rather than as a sentence written for the user (`G-3.4`).
///
/// Its own type because both equipment screens draw one, and a write that failed on the form must
/// look the same as one that failed on the list.
struct DiagnosticCard: View {
    /// What failed, in the screen's words.
    let title: Text

    /// The error's description. **Not copy** — never translated, never presented as a sentence.
    let detail: String

    /// The card.
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                title
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(verbatim: detail)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
