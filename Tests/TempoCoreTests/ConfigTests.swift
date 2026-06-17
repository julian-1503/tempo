import Testing
@testable import TempoCore

@Suite("Config parser")
struct ConfigTests {
    @Test("empty input yields an empty config")
    func empty() throws {
        #expect(try ConfigParser.parse("") == Config())
    }

    @Test("blank lines and # comments are ignored")
    func commentsAndBlanks() throws {
        let source = """

        # top-level comment
        [daemon]
        # inline comment line

        """
        #expect(try ConfigParser.parse(source) == Config())
    }

    @Test("[daemon] string keys map to their fields")
    func daemonStringKeys() throws {
        let source = """
        [daemon]
        default_scene = "morning"
        default_workspace = "T"
        """
        #expect(try ConfigParser.parse(source) ==
                Config(defaultScene: "morning", defaultWorkspace: "T"))
    }

    @Test("[daemon] managed reads a single-line string array")
    func managedArray() throws {
        let source = """
        [daemon]
        managed = ["com.apple.TextEdit", "com.brave.Browser"]
        """
        #expect(try ConfigParser.parse(source).managed ==
                ["com.apple.TextEdit", "com.brave.Browser"])
    }

    @Test("an empty managed array round-trips as []")
    func emptyArray() throws {
        let source = """
        [daemon]
        managed = []
        """
        #expect(try ConfigParser.parse(source).managed == [])
    }

    @Test("trailing comma in an array is tolerated")
    func trailingCommaArray() throws {
        let source = """
        [daemon]
        managed = ["com.apple.TextEdit",]
        """
        #expect(try ConfigParser.parse(source).managed == ["com.apple.TextEdit"])
    }

    @Test("unknown sections and unknown keys are ignored")
    func forwardCompat() throws {
        let source = """
        [daemon]
        default_scene = "morning"
        future_key = "ignored"
        [future_section]
        anything = "also ignored"
        """
        #expect(try ConfigParser.parse(source) == Config(defaultScene: "morning"))
    }

    @Test("multi-line string arrays gather across lines until the closing `]`")
    func multiLineArray() throws {
        let source = """
        [daemon]
        managed = [
          "com.apple.TextEdit",
          "com.brave.Browser",
        ]
        """
        #expect(try ConfigParser.parse(source).managed == ["com.apple.TextEdit", "com.brave.Browser"])
    }

    @Test("comments inside multi-line arrays are stripped")
    func multiLineArrayWithComments() throws {
        let source = """
        [daemon]
        managed = [
          "com.apple.TextEdit", # the writer
          "com.brave.Browser",  # the browser
        ]
        """
        #expect(try ConfigParser.parse(source).managed == ["com.apple.TextEdit", "com.brave.Browser"])
    }

    @Test("a line without `=` throws a syntax error pointing at the line")
    func missingEquals() {
        #expect(throws: ConfigParseError.syntax(line: 2, reason: "expected `key = value`")) {
            try ConfigParser.parse("[daemon]\nbroken\n")
        }
    }

    @Test("an unquoted string value throws a syntax error")
    func unquotedString() {
        #expect(throws: (any Error).self) {
            try ConfigParser.parse("[daemon]\ndefault_scene = morning\n")
        }
    }
}
