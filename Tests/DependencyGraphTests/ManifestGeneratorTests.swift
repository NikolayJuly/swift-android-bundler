// ManifestGeneratorTests.swift
@testable import DependencyGraph
import Foundation
import Testing

@Suite("ManifestGenerator")
struct ManifestGeneratorTests {

    @Test("Libraries in topological order with correct name transformation")
    func basicOrderAndNameTransformation() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libMyLibrary.so"))
        graph.addNode(makeSdk("libswiftCore.so"))
        graph.addNode(makeSdk("libdispatch.so"))

        graph.addEdge(DependencyGraphEdge(from: "libMyLibrary.so", to: "libswiftCore.so",
                                          realSymbolCount: 100, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libswiftCore.so", to: "libdispatch.so",
                                          realSymbolCount: 40, symbols: []))

        let reachable: Set<String> = ["libMyLibrary.so", "libswiftCore.so", "libdispatch.so"]
        let manifest = ManifestGenerator.generate(graph: graph,
                                                   reachableNames: reachable,
                                                   productName: "MyLibrary",
                                                   hasRealDependency: makeHasRealDep(graph))

        #expect(manifest.product == "MyLibrary")
        // Topological: dispatch first, then swiftCore, then App
        #expect(manifest.libraries == ["dispatch", "swiftCore", "MyLibrary"])
    }

    @Test("Removed libraries are not in manifest")
    func cleanupExcludesRemovedLibraries() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libApp.so"))
        graph.addNode(makeSdk("libB.so"))
        graph.addNode(makeSdk("libC.so"))

        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libB.so", realSymbolCount: 10, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libC.so", realSymbolCount: 0, symbols: []))

        // Only App and B are reachable (C was removed by cleaner)
        let reachable: Set<String> = ["libApp.so", "libB.so"]
        let manifest = ManifestGenerator.generate(graph: graph,
                                                   reachableNames: reachable,
                                                   productName: "App",
                                                   hasRealDependency: makeHasRealDep(graph))

        #expect(manifest.libraries.contains("B"))
        #expect(manifest.libraries.contains("App"))
        #expect(manifest.libraries.contains("C") == false)
        #expect(manifest.libraries.count == 2)
    }

    @Test("JSON data has correct structure")
    func jsonDataStructure() throws {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libApp.so"))
        graph.addNode(makeSdk("libswiftCore.so"))

        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libswiftCore.so",
                                          realSymbolCount: 10, symbols: []))

        let manifest = ManifestGenerator.generate(graph: graph,
                                                   reachableNames: ["libApp.so", "libswiftCore.so"],
                                                   productName: "App",
                                                   hasRealDependency: makeHasRealDep(graph))

        let data = try manifest.jsonData()
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["product"] as? String == "App")
        let libraries = parsed["libraries"] as? [String]
        #expect(libraries == manifest.libraries)
    }
}

// MARK: - Private

private extension ManifestGeneratorTests {
    func makeBuilt(_ name: String) -> DependencyGraphNode {
        DependencyGraphNode(name: name, url: URL(filePath: "/build/\(name)"), source: .built, size: 1024)
    }

    func makeSdk(_ name: String) -> DependencyGraphNode {
        DependencyGraphNode(name: name, url: URL(filePath: "/sdk/\(name)"), source: .sdk, size: 2048)
    }

    func makeHasRealDep(_ graph: DependencyGraph) -> (String, String) -> Bool {
        let realPairs: Set<String> = Set(graph.edges.filter { $0.realSymbolCount > 0 }.map { "\($0.from)->\($0.to)" })
        return { from, to in realPairs.contains("\(from)->\(to)") }
    }
}
