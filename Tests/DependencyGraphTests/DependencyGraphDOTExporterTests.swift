// DependencyGraphDOTExporterTests.swift
@testable import DependencyGraph
import Foundation
import Testing

@Suite("DependencyGraphDOTExporter")
struct DependencyGraphDOTExporterTests {

    @Test("Built nodes are lightgreen, SDK nodes are lightblue")
    func nodeColors() {
        var graph = DependencyGraph()
        graph.addNode(DependencyGraphNode(name: "libApp.so", url: URL(filePath: "/build/libApp.so"),
                                          source: .built, size: 1024))
        graph.addNode(DependencyGraphNode(name: "libswiftCore.so", url: URL(filePath: "/sdk/libswiftCore.so"),
                                          source: .sdk, size: 2048))

        let dot = DependencyGraphDOTExporter.export(graph)

        #expect(dot.contains("\"libApp.so\" [style=filled, fillcolor=lightgreen];"))
        #expect(dot.contains("\"libswiftCore.so\" [style=filled, fillcolor=lightblue];"))
    }

    @Test("Stripped edges are dashed red with 'stripped' label")
    func strippedEdgesStyling() {
        var graph = DependencyGraph()
        graph.addNode(DependencyGraphNode(name: "libA.so", url: URL(filePath: "/build/libA.so"),
                                          source: .built, size: 1024))
        graph.addNode(DependencyGraphNode(name: "libB.so", url: URL(filePath: "/sdk/libB.so"),
                                          source: .sdk, size: 2048))

        let patchEntry = PatchEntry(file: "libA.so", removeNeeded: "libB.so")

        let dot = DependencyGraphDOTExporter.export(graph, strippedEdges: [patchEntry])

        #expect(dot.contains("[style=dashed, color=red, label=\"stripped\"]"))
    }

    @Test("Active edges show symbol count label")
    func activeEdgesShowSymbolCount() {
        var graph = DependencyGraph()
        graph.addNode(DependencyGraphNode(name: "libA.so", url: URL(filePath: "/build/libA.so"),
                                          source: .built, size: 1024))
        graph.addNode(DependencyGraphNode(name: "libB.so", url: URL(filePath: "/sdk/libB.so"),
                                          source: .sdk, size: 2048))

        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libB.so",
                                          realSymbolCount: 42, symbols: []))

        let dot = DependencyGraphDOTExporter.export(graph)

        #expect(dot.contains("\"libA.so\" -> \"libB.so\" [label=\"42 symbols\"];"))
    }
}
