// ManifestGenerator.swift
import Foundation

package struct ManifestContent: Sendable {
    package let product: String
    package let libraries: [String]

    package func jsonData() throws -> Data {
        let manifest: [String: Any] = [
            "product": product,
            "libraries": libraries,
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }
}

package final class ManifestGenerator {
    private init() {}

    package static func generate(graph: DependencyGraph,
                                 reachableNames: Set<String>,
                                 productName: String,
                                 hasRealDependency: (String, String) -> Bool) -> ManifestContent {
        let ordered = graph.topologicalOrder(of: reachableNames,
                                             hasRealDependency: hasRealDependency)
        let libraryNames = ordered.map { name in
            var result = name
            if result.hasPrefix("lib") { result = String(result.dropFirst(3)) }
            if result.hasSuffix(".so") { result = String(result.dropLast(3)) }
            return result
        }
        return ManifestContent(product: productName, libraries: libraryNames)
    }
}
