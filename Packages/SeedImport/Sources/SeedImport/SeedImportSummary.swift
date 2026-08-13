/// What one import did, so that a caller can assert it did nothing.
///
/// **``writeCount`` is the number that matters and the reason this type exists.** A row count is
/// stable across a re-import whether the import wrote every row or none of them, so it cannot show
/// what the module header's no-op-save rule turns on. How many saves happened can.
public struct SeedImportSummary: Equatable, Sendable {
    /// Catalogue entries written as new rows.
    public let inserted: Int

    /// Stored rows whose seed-owned columns moved, and which were therefore saved.
    public let updated: Int

    /// Stored rows archived because the catalogue no longer lists them (`FR-1.1.5`).
    public let archived: Int

    /// Catalogue entries that needed no write — already matching, or authored by the user.
    public let unchanged: Int

    /// How many saves the import performed.
    public var writeCount: Int { inserted + updated + archived }

    /// Creates a summary. No count is validated; this describes an import that has happened.
    public init(inserted: Int, updated: Int, archived: Int, unchanged: Int) {
        self.inserted = inserted
        self.updated = updated
        self.archived = archived
        self.unchanged = unchanged
    }
}
