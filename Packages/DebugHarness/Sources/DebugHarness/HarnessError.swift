/// What can go wrong in a run that is not the store's or the seed's fault.
public enum HarnessError: Error, Equatable, Sendable {
    /// The catalogue held no exercise under the name the scenario logs against.
    ///
    /// A packaging fault rather than a runtime one: the seed ships the name this looks for, so
    /// reaching here means the catalogue was edited without the harness being told.
    case exerciseNotFound(name: String)
}
