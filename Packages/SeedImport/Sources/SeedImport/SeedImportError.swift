import SeedContent

/// Why an import did not happen.
///
/// There is one case, and the absence of the others is the contract: a payload that validates
/// imports, and a payload that does not is refused before the first save. Anything a repository
/// raises during the import propagates as a `RepositoryError` rather than being wrapped here — it
/// describes the store's state, not the payload's.
public enum SeedImportError: Error, Equatable {
    /// The payload is not fit to import, with every reason the validator found rather than the
    /// first. Nothing was written.
    case invalidPayload([SeedValidationFailure])
}
