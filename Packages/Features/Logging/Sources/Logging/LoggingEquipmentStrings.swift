import Foundation

/// ``LoggingStrings``' fourth file — `FR-1.4.2`/`FR-1.4.3`'s equipment profiles, reached from the
/// plate calculator and from Settings (`FR-1.10.3`).
///
/// **The same type in a fourth file, on `LoggingModifierStrings.swift`'s argument**: one enum is what
/// keeps a module's copy in one place, and `file_length` is what keeps that one place readable.
///
/// The middle segment is `equipment` rather than a screen name, because the two screens here are one
/// subject: a list of gyms and the form over one of them.
extension LoggingStrings {
    // MARK: - The list of gyms (FR-1.4.3, FR-1.10.3)

    /// The screen's title, and the Settings row that opens it.
    static let equipmentTitle = resource("logging.equipment.title")

    /// The heading when the user has set up no gym at all.
    static let equipmentEmptyHeadline = resource("logging.equipment.empty.headline")

    /// `FR-1.13.2`'s guidance towards the first one, naming what a gym is made of here.
    static let equipmentEmptyMessage = resource("logging.equipment.empty.message")

    /// The command that adds one.
    static let equipmentAddAction = resource("logging.equipment.add.action")

    /// The badge on the gym every loading is worked out against.
    static let equipmentActiveBadge = resource("logging.equipment.active.badge")

    /// The command that switches to a gym (`FR-1.4.3`).
    static let equipmentUseAction = resource("logging.equipment.use.action")

    /// What the list says when the user has gyms but none is in use — the state deleting the active
    /// one leaves behind, which no badge can show because the badge is what is missing.
    static let equipmentNoneActive = resource("logging.equipment.none-active")

    /// The command that opens one for editing.
    static let equipmentEditAction = resource("logging.equipment.edit.action")

    /// The heading when the profiles could not be read.
    static let equipmentErrorHeadline = resource("logging.equipment.error.headline")

    /// What that costs the screen, and what a retry would do.
    static let equipmentErrorMessage = resource("logging.equipment.error.message")

    /// The title over a write that failed. The diagnostic beneath it is not copy (`G-3.4`).
    static let equipmentWriteErrorTitle = resource("logging.equipment.write-error.title")

    // MARK: - The editor (FR-1.4.2)

    /// The form's title while a gym is being added.
    static let equipmentCreateTitle = resource("logging.equipment.create.title")

    /// The form's title while one is being edited.
    static let equipmentEditTitle = resource("logging.equipment.edit.title")

    /// The name field (`FR-1.4.3`).
    static let equipmentNameLabel = resource("logging.equipment.name.label")

    /// That a name is the user's own word for the place, and optional.
    static let equipmentNameHint = resource("logging.equipment.name.hint")

    /// The bar's own mass.
    static let equipmentBarLabel = resource("logging.equipment.bar.label")

    /// The collar field, which names **one** collar in the label rather than in a placeholder — the
    /// factor-of-two error this field exists to prevent is invisible once it is stored.
    static let equipmentCollarLabel = resource("logging.equipment.collar.label")

    /// The same fact said again as the field's hint, with what to enter for a bar loaded without
    /// them.
    static let equipmentCollarHint = resource("logging.equipment.collar.hint")

    /// The heading over the plate list.
    static let equipmentPlatesSection = resource("logging.equipment.plates.section")

    /// That a gym with no plates is a real profile rather than an unfinished one.
    static let equipmentPlatesHint = resource("logging.equipment.plates.hint")

    /// One row's denomination.
    static let equipmentPlateLabel = resource("logging.equipment.plate.label")

    /// One row's count, which is **pairs** and says so: a plate goes on both ends of the bar.
    static let equipmentPairsLabel = resource("logging.equipment.pairs.label")

    /// The command that adds a denomination.
    static let equipmentAddPlateAction = resource("logging.equipment.add-plate.action")

    /// The command that takes one away.
    static let equipmentRemovePlateAction = resource("logging.equipment.remove-plate.action")

    /// The command that writes the profile.
    static let equipmentSaveAction = resource("logging.equipment.save.action")

    /// The way out without writing anything.
    static let equipmentCancelAction = resource("logging.equipment.cancel.action")

    /// The command that deletes the profile being edited.
    static let equipmentDeleteAction = resource("logging.equipment.delete.action")

    /// The deletion's confirmation.
    static let equipmentDeleteConfirmTitle = resource("logging.equipment.delete-confirm.title")

    /// What deleting a gym costs, including the case where it is the one in use.
    static let equipmentDeleteConfirmMessage = resource("logging.equipment.delete-confirm.message")

    /// The confirming command.
    static let equipmentDeleteConfirmAction = resource("logging.equipment.delete-confirm.action")

    /// The way out of the confirmation.
    static let equipmentDeleteConfirmCancel = resource("logging.equipment.delete-confirm.cancel")

    // MARK: - Refusals (FR-1.13.3)

    /// Why a draft will not save, in the user's terms.
    ///
    /// **A function over the refusal rather than one string per case at the call site**, so the
    /// screen cannot draw a message for a refusal it did not get, and adding a case to
    /// ``EquipmentDraftRefusal`` fails to compile until it has copy.
    ///
    /// - Parameter refusal: What the draft refused on.
    /// - Returns: The sentence.
    static func equipmentRefusal(_ refusal: EquipmentDraftRefusal) -> LocalizedStringResource {
        switch refusal {
        case .barNotAWeight: resource("logging.equipment.refusal.bar")
        case .collarNotAWeight: resource("logging.equipment.refusal.collar")
        case .plateNotAWeight: resource("logging.equipment.refusal.plate")
        case .pairCountNotACount: resource("logging.equipment.refusal.pairs")
        case .repeatedDenomination: resource("logging.equipment.refusal.repeated")
        case .inventoryOverflows: resource("logging.equipment.refusal.overflow")
        }
    }

    /// How many pairs of a denomination a gym has, as one line of the summary.
    ///
    /// **The plate arrives rendered and the count does not**, and the asymmetry is what the
    /// `.stringsdict` needs: `AppFormat` decides how a weight reads and a catalogue could not, while
    /// the count has to stay a number for the plural to agree with it — "20 kg × 1 pair".
    ///
    /// - Parameters:
    ///   - plate: The denomination, formatted.
    ///   - pairs: How many pairs.
    /// - Returns: The item.
    static func equipmentPlatePairs(plate: String, pairs: Int) -> LocalizedStringResource {
        resource("logging.equipment.plate-pairs \(plate) \(pairs)")
    }

    /// A gym that stocks nothing — an answer rather than a blank.
    static let equipmentNoPlates = resource("logging.equipment.no-plates")

    /// The equipment screens' copy, for ``LoggingStrings/all``.
    static var allEquipmentStrings: [LocalizedStringResource] {
        [
            equipmentTitle, equipmentEmptyHeadline, equipmentEmptyMessage, equipmentAddAction,
            equipmentActiveBadge, equipmentUseAction, equipmentNoneActive, equipmentEditAction,
            equipmentErrorHeadline,
            equipmentErrorMessage, equipmentWriteErrorTitle, equipmentCreateTitle,
            equipmentEditTitle, equipmentNameLabel, equipmentNameHint, equipmentBarLabel,
            equipmentCollarLabel, equipmentCollarHint, equipmentPlatesSection, equipmentPlatesHint,
            equipmentPlateLabel, equipmentPairsLabel, equipmentAddPlateAction,
            equipmentRemovePlateAction, equipmentSaveAction, equipmentCancelAction,
            equipmentDeleteAction, equipmentDeleteConfirmTitle, equipmentDeleteConfirmMessage,
            equipmentDeleteConfirmAction, equipmentDeleteConfirmCancel, equipmentNoPlates,
            equipmentPlatePairs(plate: "", pairs: 1), equipmentPlatePairs(plate: "", pairs: 2),
        ] + Self.allRefusals.map(equipmentRefusal)
    }

    /// Every refusal the editor can report, so ``allEquipmentStrings`` names each one's copy.
    ///
    /// Written out rather than derived from a `CaseIterable`: the conformance would exist only for
    /// this list, and a case added without copy is what this array is here to catch.
    private static var allRefusals: [EquipmentDraftRefusal] {
        [
            .barNotAWeight, .collarNotAWeight, .plateNotAWeight, .pairCountNotACount,
            .repeatedDenomination, .inventoryOverflows,
        ]
    }
}
