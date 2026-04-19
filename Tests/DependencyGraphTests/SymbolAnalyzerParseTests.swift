// SymbolAnalyzerParseTests.swift
@testable import DependencyGraph
import Testing

@Suite("SymbolAnalyzer.parseNmOutput")
struct SymbolAnalyzerParseTests {

    @Test("Parses standard llvm-nm output with address, type, and symbol")
    func parseStandardOutput() {
        let output = """
        0000000000001234 T _swift_allocObject
        00000000000056ab T _swift_release
        0000000000007800 D _globalVar
        """

        let symbols = SymbolAnalyzer.parseNmOutput(output)

        #expect(symbols == ["_swift_allocObject", "_swift_release", "_globalVar"])
    }

    @Test("Parses undefined-only output (spaces + U + symbol)")
    func parseUndefinedOutput() {
        let output = """
                         U _swift_allocObject
                         U _swift_release
                         U _objc_msgSend
        """

        let symbols = SymbolAnalyzer.parseNmOutput(output)

        #expect(symbols == ["_swift_allocObject", "_swift_release", "_objc_msgSend"])
    }

    @Test("Empty input returns empty set")
    func emptyInput() {
        #expect(SymbolAnalyzer.parseNmOutput("").isEmpty)
        #expect(SymbolAnalyzer.parseNmOutput("   \n  \n").isEmpty)
    }
}
