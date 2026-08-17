import Testing

@testable import RemoteFetch

@Suite("AppVersion")
struct AppVersionTests {
    @Test("A dotted version parses and keeps the text it was written with")
    func parsesDottedVersion() throws {
        let version = try #require(AppVersion("1.2.3"))
        #expect(version.text == "1.2.3")
        #expect(version.description == "1.2.3")
    }

    @Test("One field is a version")
    func singleFieldIsAVersion() throws {
        #expect(try #require(AppVersion("2")) == #require(AppVersion("2.0.0")))
    }

    @Test("Trailing zeros do not change which version it is")
    func trailingZerosAreNotSignificant() throws {
        #expect(try #require(AppVersion("1.0")) == #require(AppVersion("1.0.0")))
        #expect(try #require(AppVersion("1.2")) == #require(AppVersion("1.2.0.0")))
        #expect(try #require(AppVersion("0")) == #require(AppVersion("0.0")))
    }

    @Test("A zero in the middle is significant")
    func interiorZerosAreSignificant() throws {
        #expect(try #require(AppVersion("1.0.3")) != #require(AppVersion("1.3")))
    }

    @Test("Fields compare as numbers, not as text")
    func fieldsCompareNumerically() throws {
        // The whole point: "1.10" sorts below "1.9" as a string and above it as a version.
        #expect(try #require(AppVersion("1.9")) < #require(AppVersion("1.10")))
        #expect(try #require(AppVersion("2.0")) > #require(AppVersion("1.99.99")))
    }

    @Test("A longer version is above the prefix it extends")
    func extraFieldsCountAsZero() throws {
        #expect(try #require(AppVersion("1.2")) < #require(AppVersion("1.2.1")))
        #expect(try #require(AppVersion("1.2.1")) > #require(AppVersion("1.2")))
    }

    @Test("A version is not below itself")
    func orderIsStrict() throws {
        let version = try #require(AppVersion("3.4.5"))
        #expect(!(version < version))
        #expect(version <= version)
    }

    @Test(
        "Anything that is not digits and dots is not a version",
        arguments: [
            "",
            " ",
            "1.",
            ".1",
            "1..2",
            "v1.0",
            "abc",
            "1.0.0-beta",
            "1.0 (42)",
            "+1.0",
            "-1.0",
            "1.0\n",
            "1٫0",
            // Digits, but not ASCII ones — refused by `Int(_:)`, which takes no other numeral.
            "１.０",
            // Too large for Int, which is refused rather than truncated to something orderable.
            "99999999999999999999.0",
        ])
    func rejectsNonVersions(text: String) {
        #expect(AppVersion(text) == nil)
    }
}
