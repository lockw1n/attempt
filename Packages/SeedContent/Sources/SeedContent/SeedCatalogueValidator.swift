import Foundation

/// Checks that a payload is fit to ship (`TR-0.5.1`).
///
/// **It reports every failure it finds, not the first.** The audience is authoring eighty entries by
/// hand, and a validator that stops at one turns that into eighty runs.
public enum SeedCatalogueValidator {
    /// Decodes and validates a payload as it exists on disk or over the wire.
    ///
    /// This is the entry point that means anything, because three of the failure modes — a malformed
    /// UUID, a missing field, a misspelled key — cannot be expressed by a value built in Swift.
    /// A payload that fails to decode yields exactly one failure: there is nothing to check.
    ///
    /// - Parameters:
    ///   - data: The payload's bytes.
    ///   - minimumExercises: How many entries the caller requires. `TR-0.5.1`'s floor of eighty
    ///     belongs to the shipped catalogue's own test, not to every call.
    public static func validate(_ data: Data, minimumExercises: Int = 1) -> [SeedValidationFailure] {
        do {
            let catalogue = try JSONDecoder().decode(SeedCatalogue.self, from: data)
            return validate(catalogue, minimumExercises: minimumExercises)
        } catch SeedDecodingFailure.unrecognisedField(let name) {
            return [.unrecognisedField(name)]
        } catch {
            return [.undecodable(describe(error))]
        }
    }

    /// Validates an already-decoded payload.
    ///
    /// - Parameters:
    ///   - catalogue: The decoded payload.
    ///   - minimumExercises: How many entries the caller requires.
    public static func validate(
        _ catalogue: SeedCatalogue,
        minimumExercises: Int = 1
    ) -> [SeedValidationFailure] {
        var failures: [SeedValidationFailure] = []

        if catalogue.schemaVersion != SeedCatalogue.supportedSchemaVersion {
            failures.append(.unsupportedSchemaVersion(catalogue.schemaVersion))
        }
        if catalogue.revision < 1 {
            failures.append(.nonPositiveRevision(catalogue.revision))
        }
        if catalogue.exercises.count < minimumExercises {
            failures.append(
                .tooFewExercises(count: catalogue.exercises.count, minimum: minimumExercises))
        }

        // First occurrence wins, so a duplicate cannot silently redirect a parent edge.
        var firstByID: [UUID: SeedExercise] = [:]
        for exercise in catalogue.exercises {
            if firstByID[exercise.id] == nil {
                firstByID[exercise.id] = exercise
            } else {
                failures.append(.duplicateID(exercise.id))
            }
        }

        for exercise in catalogue.exercises {
            failures.append(contentsOf: entryFailures(exercise, resolving: firstByID))
        }
        failures.append(contentsOf: parentCycles(in: catalogue.exercises, resolving: firstByID))
        return failures
    }

    /// The failures visible from one entry, with the rest of the payload available only for
    /// resolving its parent.
    private static func entryFailures(
        _ exercise: SeedExercise,
        resolving firstByID: [UUID: SeedExercise]
    ) -> [SeedValidationFailure] {
        var failures: [SeedValidationFailure] = []

        if exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append(.blankName(exercise.id))
        }
        // Walked rather than named: `laterality` is the only one of the four whose own `Decodable`
        // throws, so a rule written out per field passes while three of them go unchecked.
        for field in SeedVocabularyField.allCases {
            let rawValue = exercise.rawValue(for: field)
            if !field.accepts(rawValue) {
                failures.append(
                    .unknownVocabulary(exercise: exercise.id, field: field, value: rawValue))
            }
        }
        if exercise.implements < 1 {
            failures.append(
                .nonPositiveImplementCount(exercise: exercise.id, count: exercise.implements))
        }
        if let parent = exercise.parentExerciseID, firstByID[parent] == nil {
            failures.append(.danglingParent(exercise: exercise.id, parent: parent))
        }
        return failures
    }

    /// Every parent chain that closes on itself, each reported once.
    ///
    /// An entry has at most one parent, so the chains form a functional graph and a cycle is found
    /// by walking upwards. Chains already walked are remembered, which keeps the whole pass linear
    /// and — more usefully — reports one cycle once however many entries hang below it.
    private static func parentCycles(
        in exercises: [SeedExercise],
        resolving firstByID: [UUID: SeedExercise]
    ) -> [SeedValidationFailure] {
        var failures: [SeedValidationFailure] = []
        var settled: Set<UUID> = []

        for exercise in exercises where !settled.contains(exercise.id) {
            var path: [UUID] = []
            var onPath: Set<UUID> = []
            var current: UUID? = exercise.id

            while let id = current {
                if onPath.contains(id) {
                    failures.append(.parentCycle(Array(path.drop(while: { $0 != id }))))
                    break
                }
                if settled.contains(id) {
                    break
                }
                path.append(id)
                onPath.insert(id)
                // A parent the payload does not contain ends the walk; `danglingParent` reports it.
                current = firstByID[id]?.parentExerciseID
            }
            settled.formUnion(path)
        }
        return failures
    }

    /// A decoding error as one line naming the key and what was wrong with it.
    private static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else { return String(describing: error) }

        let context: DecodingError.Context
        switch decodingError {
        case .typeMismatch(_, let found), .valueNotFound(_, let found), .keyNotFound(_, let found):
            context = found
        case .dataCorrupted(let found):
            context = found
        @unknown default:
            return String(describing: error)
        }

        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }
}
