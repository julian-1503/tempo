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

    @Test("[daemon] default_workspace maps to its field")
    func daemonDefaultWorkspace() throws {
        let source = """
        [daemon]
        default_workspace = "T"
        """
        #expect(try ConfigParser.parse(source) == Config(defaultWorkspace: "T"))
    }

    @Test("[daemon] workspaces reads a single-line string array")
    func workspacesArray() throws {
        let source = """
        [daemon]
        workspaces = ["1", "T", "B", "Q"]
        """
        #expect(try ConfigParser.parse(source).workspaces == ["1", "T", "B", "Q"])
    }

    @Test("an empty workspaces array round-trips as []")
    func emptyArray() throws {
        let source = """
        [daemon]
        workspaces = []
        """
        #expect(try ConfigParser.parse(source).workspaces == [])
    }

    @Test("trailing comma in an array is tolerated")
    func trailingCommaArray() throws {
        let source = """
        [daemon]
        workspaces = ["1",]
        """
        #expect(try ConfigParser.parse(source).workspaces == ["1"])
    }

    @Test("unknown sections and unknown keys are ignored")
    func forwardCompat() throws {
        let source = """
        [daemon]
        default_workspace = "T"
        future_key = "ignored"
        [future_section]
        anything = "also ignored"
        """
        #expect(try ConfigParser.parse(source) == Config(defaultWorkspace: "T"))
    }

    @Test("multi-line string arrays gather across lines until the closing `]`")
    func multiLineArray() throws {
        let source = """
        [daemon]
        workspaces = [
          "1",
          "T",
        ]
        """
        #expect(try ConfigParser.parse(source).workspaces == ["1", "T"])
    }

    @Test("comments inside multi-line arrays are stripped")
    func multiLineArrayWithComments() throws {
        let source = """
        [daemon]
        workspaces = [
          "1", # the default
          "T", # terminal
        ]
        """
        #expect(try ConfigParser.parse(source).workspaces == ["1", "T"])
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
            try ConfigParser.parse("[daemon]\ndefault_workspace = T\n")
        }
    }
}
