// ProductMatcherTests.swift

import Foundation
import Testing

@testable import SwiftAndroidBuilder

@Suite("ProductMatcher")
struct ProductMatcherTests {

    @Test("Matches products to correct sources")
    func matchHappyPath() throws {
        let products = ["Analytics", "Payments", "ModuleB"]
        let sources = [ProductMatcher.SourcePackage(path: URL(filePath: "/ws/pkg-a"),
                                                     productNames: ["Analytics", "HelperLib"]),
                       ProductMatcher.SourcePackage(path: URL(filePath: "/ws/pkg-b"),
                                                     productNames: ["Payments", "ModuleB"])]

        let matched = try ProductMatcher.match(products: products, sources: sources)

        #expect(matched.count == 3)
        #expect(matched["Analytics"]?.packagePath == URL(filePath: "/ws/pkg-a"))
        #expect(matched["Payments"]?.packagePath == URL(filePath: "/ws/pkg-b"))
        #expect(matched["ModuleB"]?.packagePath == URL(filePath: "/ws/pkg-b"))
    }

    @Test("Throws on missing product and on ambiguous product")
    func matchErrors() {
        let sources = [ProductMatcher.SourcePackage(path: URL(filePath: "/ws/a"),
                                                     productNames: ["SharedLib"]),
                       ProductMatcher.SourcePackage(path: URL(filePath: "/ws/b"),
                                                     productNames: ["SharedLib"])]

        // Product not found in any source
        #expect(throws: (any Error).self) {
            try ProductMatcher.match(products: ["Unknown"],
                                     sources: [ProductMatcher.SourcePackage(path: URL(filePath: "/ws/a"),
                                                                            productNames: ["Other"])])
        }

        // Product found in multiple sources
        #expect(throws: (any Error).self) {
            try ProductMatcher.match(products: ["SharedLib"],
                                     sources: sources)
        }
    }
}
