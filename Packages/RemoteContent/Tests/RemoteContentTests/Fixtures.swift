import Foundation
import Testing

/// The bytes of a fixture, loaded the way the shipped file will be.
func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
        "no fixture named \(name).json")
    return try Data(contentsOf: url)
}
