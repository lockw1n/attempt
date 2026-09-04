import Foundation
import RepositoryInterface

/// How ``TrainingLogArchive`` is written and read back (`FR-1.11.1`, `FR-1.11.3`).
///
/// **The encoder's configuration is the wire format here, not the `Codable` conformances.**
/// `RecordCoding.swift` pins the keys and the nested shapes and then deliberately leaves two things
/// to whichever caller encodes: the date representation and the key order. This is that caller, and
/// both are decided here so that one file answers them for the export, for `FR-1.11.3`'s backup and
/// for the restore that reads either.
extension TrainingLogArchive {
    /// The encoder every archive is written with.
    ///
    /// **Dates are `deferredToDate`, and that is `FR-1.11.1`'s word "lossless" choosing rather than
    /// readability choosing.** Measured over five dates spanning the representable range: ISO-8601
    /// round-trips 2 of 5 exactly and 3 of 5 with fractional seconds, seconds-since-1970 4 of 5, and
    /// only the deferred form all 5. So a timestamp here is **a `Double` of seconds since
    /// 2001-01-01T00:00:00Z**, which is what a reader outside Foundation has to be told; the
    /// human-readable dates are `FR-1.11.1`'s other half, the CSV. Writing both forms was refused for
    /// rule 6's reason in `RecordCoding.swift`: a format that admits two encodings of one value is a
    /// format two writers can disagree inside.
    ///
    /// **Keys are sorted, so the same store exports the same bytes.** Without it `JSONEncoder` emits
    /// a keyed container in per-process hash order and two exports of an unchanged log differ —
    /// which makes a backup impossible to diff and a golden file impossible to write.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The decoder that reads one back, configured to match ``encoder`` exactly.
    ///
    /// **`nonisolated`, with ``decoded(from:)``**, so that a restore can decode a chosen file off
    /// the main thread (see ``RestoreState/archive(at:)``). Free of the usual caveat: this is a
    /// computed property handing back a fresh decoder, so there is no shared instance for two
    /// threads to share.
    nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    /// Encodes this archive as the bytes an export or a backup file carries.
    ///
    /// - Returns: The JSON payload.
    /// - Throws: Whatever `JSONEncoder` throws.
    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    /// Reads an archive back out of a file.
    ///
    /// - Parameter data: The JSON payload.
    /// - Returns: The archive it carries.
    /// - Throws: Whatever `JSONDecoder` throws — a truncated or foreign file is corruption rather
    ///   than a newer version, which is rule 5 of `RecordCoding.swift`.
    nonisolated static func decoded(from data: Data) throws -> Self {
        try decoder.decode(Self.self, from: data)
    }

    /// Reads the envelope, defaulting the sections a training-log export does not write.
    ///
    /// **Hand-written rather than synthesised, and that is what makes version 2 readable by a
    /// version 1 file.** Synthesis makes every non-optional key required, so adding
    /// ``TrainingLogArchive/equipment``, ``TrainingLogArchive/trainingMaxes`` and
    /// ``TrainingLogArchive/contents`` would have made every file written before them undecodable —
    /// a format that breaks its own past files is not a backup format. Rule 3 of
    /// `RecordCoding.swift` says an absent value is an omitted key, and this reads the sections that
    /// way: absent means the section is empty, which for a file that never carried one is true.
    ///
    /// **The four routine sections and the training-max history are read the same way, so a version
    /// 2 backup decodes here with four empty sections and a version 3 one with five** — which is
    /// what those files hold. That is what rule 3 buys, and it is only ever about reading an older
    /// file: it is not the reason ``TrainingLogArchive/currentFormatVersion`` moved to 3 and then 4,
    /// which is about the other direction and argued there.
    ///
    /// **``TrainingLogArchive/formatVersion`` is carried as written rather than replaced with the
    /// current one.** It is what `FR-1.11.4`'s restore refuses a future file on, and a reader that
    /// overwrote it with its own number would leave that refusal nothing to test.
    ///
    /// - Parameter decoder: The decoder reading the file.
    /// - Throws: A `DecodingError` for a missing required key, a wrong type, or a
    ///   ``TrainingLogArchive/Contents`` spelling this build does not know.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            formatVersion: try container.decode(Int.self, forKey: .formatVersion),
            contents: try Self.decodeContents(from: container),
            exportedAt: try container.decode(Date.self, forKey: .exportedAt),
            exercises: try container.decode([Exercise].self, forKey: .exercises),
            sessions: try container.decode([WorkoutSession].self, forKey: .sessions),
            entries: try container.decode([ExerciseEntry].self, forKey: .entries),
            sets: try container.decode([SetEntry].self, forKey: .sets),
            bodyweight: try container.decode([BodyweightEntry].self, forKey: .bodyweight),
            equipment: try container.decodeIfPresent([EquipmentProfile].self, forKey: .equipment)
                ?? [],
            trainingMaxes: try container.decodeIfPresent(
                [TrainingMaxEntry].self, forKey: .trainingMaxes) ?? [],
            trainingMaxHistory: try container.decodeIfPresent(
                [TrainingMaxHistoryEntry].self, forKey: .trainingMaxHistory) ?? [],
            routines: try container.decodeIfPresent([Routine].self, forKey: .routines) ?? [],
            routineExercises: try container.decodeIfPresent(
                [RoutineExercise].self, forKey: .routineExercises) ?? [],
            routineTargetGroups: try container.decodeIfPresent(
                [RoutineTargetGroup].self, forKey: .routineTargetGroups) ?? [],
            plannedTargets: try container.decodeIfPresent(
                [PlannedTargetGroup].self, forKey: .plannedTargets) ?? [],
            settings: try container.decodeIfPresent(UserSettings.self, forKey: .settings))
    }

    /// Which file this is, for a payload that may predate the question being asked.
    ///
    /// **Absent resolves to ``TrainingLogArchive/Contents/trainingLog``, and that is a fact rather
    /// than a default**: version 1 wrote exports and nothing else, so a file with no `contents` key
    /// *is* an export. An unrecognised spelling is a different matter and throws — see
    /// ``TrainingLogArchive/Contents``.
    ///
    /// - Parameter container: The envelope's keyed container.
    /// - Returns: What the file says it holds.
    /// - Throws: A `DecodingError.dataCorruptedError` for a spelling this build does not know.
    private nonisolated static func decodeContents(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Contents {
        guard let raw = try container.decodeIfPresent(String.self, forKey: .contents) else {
            return .trainingLog
        }
        guard let contents = Contents(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .contents,
                in: container,
                debugDescription: "unrecognised archive contents \"\(raw)\"")
        }
        return contents
    }

    /// Writes the envelope, omitting the sections this file does not carry.
    ///
    /// **An empty section is omitted rather than written as `[]`**, which is rule 3's shape applied
    /// one level up: an export writes the keys version 1 wrote plus
    /// ``TrainingLogArchive/contents``, so the bytes say what the file is without also claiming to
    /// hold three tables it was never asked for. The five log sections are written whatever is in
    /// them — they are what every archive is, and a reader that met no `sets` key would be reading a
    /// file this version cannot have produced.
    ///
    /// - Parameter encoder: The encoder writing the file.
    /// - Throws: Whatever the encoder throws.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(contents.rawValue, forKey: .contents)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(exercises, forKey: .exercises)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(entries, forKey: .entries)
        try container.encode(sets, forKey: .sets)
        try container.encode(bodyweight, forKey: .bodyweight)
        if !equipment.isEmpty { try container.encode(equipment, forKey: .equipment) }
        if !trainingMaxes.isEmpty { try container.encode(trainingMaxes, forKey: .trainingMaxes) }
        if !trainingMaxHistory.isEmpty {
            try container.encode(trainingMaxHistory, forKey: .trainingMaxHistory)
        }
        if !routines.isEmpty { try container.encode(routines, forKey: .routines) }
        if !routineExercises.isEmpty {
            try container.encode(routineExercises, forKey: .routineExercises)
        }
        if !routineTargetGroups.isEmpty {
            try container.encode(routineTargetGroups, forKey: .routineTargetGroups)
        }
        if !plannedTargets.isEmpty { try container.encode(plannedTargets, forKey: .plannedTargets) }
        try container.encodeIfPresent(settings, forKey: .settings)
    }
}
