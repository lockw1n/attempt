import Foundation

/// How ``TrainingLogArchive`` is written and read back (`FR-1.11.1`).
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
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    /// Encodes this archive as the bytes an export file carries.
    ///
    /// - Returns: The JSON payload.
    /// - Throws: Whatever `JSONEncoder` throws.
    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    /// Reads an archive back out of an export file.
    ///
    /// - Parameter data: The JSON payload.
    /// - Returns: The archive it carries.
    /// - Throws: Whatever `JSONDecoder` throws — a truncated or foreign file is corruption rather
    ///   than a newer version, which is rule 5 of `RecordCoding.swift`.
    static func decoded(from data: Data) throws -> Self {
        try decoder.decode(Self.self, from: data)
    }
}
