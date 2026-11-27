// PackageDumpParserTests.swift

import Testing

@testable import SwiftAndroidBuilder

@Suite("PackageDumpParser")
struct PackageDumpParserTests {

    @Test("Extracts library products from realistic dump-package output, filters executables")
    func parseMixedProducts() throws {
        // Covers: static/dynamic/automatic libraries extracted, executables filtered out, sorted output
        let json = """
        {
          "name": "complex-package",
          "products": [
            { "name": "StaticLib", "type": { "library": ["static"] }, "targets": ["StaticLib"], "settings": [] },
            { "name": "DynamicLib", "type": { "library": ["dynamic"] }, "targets": ["DynamicLib"], "settings": [] },
            { "name": "AutoLib", "type": { "library": ["automatic"] }, "targets": ["AutoLib"], "settings": [] },
            { "name": "my-cli", "type": { "executable": null }, "targets": ["CLI"], "settings": [] },
            { "name": "another-tool", "type": { "executable": null }, "targets": ["Tool"], "settings": [] }
          ]
        }
        """
        let products = try PackageDumpParser.parseLibraryProductNames(from: json)
        #expect(products == ["AutoLib", "DynamicLib", "StaticLib"])
    }

    /// Only targets of type `test` come back, sorted; regular, executable and plugin targets are left out.
    @Test
    func parseTestTargets() throws {
        let json = """
        {
          "name": "package",
          "products": [],
          "targets": [
            { "name": "Lib", "type": "regular" },
            { "name": "ZTests", "type": "test" },
            { "name": "Tool", "type": "executable" },
            { "name": "ATests", "type": "test" },
            { "name": "Plugin", "type": "plugin" }
          ]
        }
        """
        let targets = try PackageDumpParser.parseTestTargetNames(from: json)
        #expect(targets == ["ATests", "ZTests"])
    }
}
