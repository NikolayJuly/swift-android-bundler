// DependencyGraphTests.swift
@testable import DependencyGraph
import Foundation
import Testing

@Suite("DependencyGraph")
struct DependencyGraphTests {

    // MARK: - DependencyGraphCleaner

    @Test("BFS follows real edges only")
    func cleanFollowsRealEdges() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libA.so"))
        graph.addNode(makeSdk("libB.so"))
        graph.addNode(makeSdk("libC.so"))
        graph.addNode(makeSdk("libD.so"))

        // A -> B (real), B -> C (real), A -> D (real)
        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libB.so", realSymbolCount: 10, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libB.so", to: "libC.so", realSymbolCount: 5, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libD.so", realSymbolCount: 3, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libA.so"],
                                                  protectedLibraries: [],
                                                  hasRealDependency: makeHasRealDep(graph))

        #expect(result.reachableNodes == ["libA.so", "libB.so", "libC.so", "libD.so"])
    }

    @Test("Phantom edges produce removed nodes and patch entries")
    func cleanPhantomEdgesProduceRemovedAndPatches() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libA.so"))
        graph.addNode(makeSdk("libB.so"))
        graph.addNode(makeSdk("libC.so"))

        // A -> B (real), A -> C (phantom)
        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libB.so", realSymbolCount: 10, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libC.so", realSymbolCount: 0, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libA.so"],
                                                  protectedLibraries: [],
                                                  hasRealDependency: makeHasRealDep(graph))

        #expect(result.reachableNodes.contains("libB.so"))
        #expect(result.reachableNodes.contains("libC.so") == false)
        #expect(result.removedNodes.contains("libC.so"))

        // A -> C is phantom and A is reachable → patch entry to remove C from A
        #expect(result.patchEntries.contains(where: { $0.file == "libA.so" && $0.removeNeeded == "libC.so" }))
    }

    @Test("Protected library with only phantom edges is still reachable")
    func cleanProtectedLibraryAlwaysReachable() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libMyLibrary.so"))
        graph.addNode(makeBuilt("libSwiftJava.so"))
        graph.addNode(makeSdk("libswiftCore.so"))

        // MyLibrary -> SwiftJava (phantom), SwiftJava -> swiftCore (real)
        graph.addEdge(DependencyGraphEdge(from: "libMyLibrary.so", to: "libSwiftJava.so",
                                          realSymbolCount: 0, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libSwiftJava.so", to: "libswiftCore.so",
                                          realSymbolCount: 42, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libMyLibrary.so"],
                                                  protectedLibraries: ["libSwiftJava.so"],
                                                  hasRealDependency: makeHasRealDep(graph))

        #expect(result.reachableNodes.contains("libSwiftJava.so"))
        #expect(result.reachableNodes.contains("libswiftCore.so"))
    }

    @Test("Protected library transitive deps are also reachable")
    func cleanProtectedLibraryTransitiveDepsReachable() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libMyLibrary.so"))
        graph.addNode(makeBuilt("libSwiftJava.so"))
        graph.addNode(makeSdk("libswiftCore.so"))
        graph.addNode(makeSdk("libFoundation.so"))

        graph.addEdge(DependencyGraphEdge(from: "libMyLibrary.so", to: "libSwiftJava.so",
                                          realSymbolCount: 0, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libSwiftJava.so", to: "libswiftCore.so",
                                          realSymbolCount: 42, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libswiftCore.so", to: "libFoundation.so",
                                          realSymbolCount: 10, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libMyLibrary.so"],
                                                  protectedLibraries: ["libSwiftJava.so"],
                                                  hasRealDependency: makeHasRealDep(graph))

        #expect(result.reachableNodes.contains("libswiftCore.so"))
        #expect(result.reachableNodes.contains("libFoundation.so"))
    }

    @Test("No patch entries for protected library phantom edge")
    func cleanNoPatchForProtectedLib() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libMyLibrary.so"))
        graph.addNode(makeBuilt("libSwiftJava.so"))

        graph.addEdge(DependencyGraphEdge(from: "libMyLibrary.so", to: "libSwiftJava.so",
                                          realSymbolCount: 0, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libMyLibrary.so"],
                                                  protectedLibraries: ["libSwiftJava.so"],
                                                  hasRealDependency: makeHasRealDep(graph))

        // SwiftJava is protected → not removed → no patch entry
        #expect(result.patchEntries.isEmpty)
    }

    @Test("Patch entries only from reachable files, not from removed ones")
    func cleanPatchEntriesOnlyFromReachable() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libApp.so"))
        graph.addNode(makeSdk("libX.so"))
        graph.addNode(makeSdk("libY.so"))

        // App -> X (phantom), X -> Y (phantom)
        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libX.so",
                                          realSymbolCount: 0, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libX.so", to: "libY.so",
                                          realSymbolCount: 0, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libApp.so"],
                                                  protectedLibraries: [],
                                                  hasRealDependency: makeHasRealDep(graph))

        // Only App -> X patch entry (App is reachable). No X -> Y (X is removed).
        #expect(result.patchEntries.count == 1)
        #expect(result.patchEntries.first?.file == "libApp.so")
        #expect(result.patchEntries.first?.removeNeeded == "libX.so")
    }

    @Test("Every patch entry file must be in reachable set")
    func cleanAllPatchFilesAreReachable() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libApp.so"))
        graph.addNode(makeSdk("libA.so"))
        graph.addNode(makeSdk("libB.so"))
        graph.addNode(makeSdk("libC.so"))

        // App -> A (real), A -> B (phantom), App -> C (phantom)
        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libA.so",
                                          realSymbolCount: 10, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libB.so",
                                          realSymbolCount: 0, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libC.so",
                                          realSymbolCount: 0, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libApp.so"],
                                                  protectedLibraries: [],
                                                  hasRealDependency: makeHasRealDep(graph))

        // Every file in patchEntries must be in reachableNodes (it will be copied to destination)
        for entry in result.patchEntries {
            #expect(result.reachableNodes.contains(entry.file),
                    "Patch entry file \(entry.file) must be in reachable set to exist in destination")
        }

        // Sanity: we expect patch entries for App->C and A->B
        #expect(result.patchEntries.count == 2)
    }

    @Test("Phantom library is excluded even when only referenced from SDK")
    func cleanSdkPhantomLibraryExcluded() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libApp.so"))
        graph.addNode(makeSdk("libFoundationEssentials.so"))
        graph.addNode(makeSdk("libswift_Builtin_float.so"))

        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libFoundationEssentials.so",
                                          realSymbolCount: 30, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libFoundationEssentials.so", to: "libswift_Builtin_float.so",
                                          realSymbolCount: 0, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libApp.so"],
                                                  protectedLibraries: [],
                                                  hasRealDependency: makeHasRealDep(graph))

        #expect(result.reachableNodes.contains("libswift_Builtin_float.so") == false)
        #expect(result.patchEntries.contains(where: { $0.file == "libFoundationEssentials.so"
                                                       && $0.removeNeeded == "libswift_Builtin_float.so" }))
    }

    @Test("Built phantom edge correctly excluded")
    func cleanBuiltPhantomEdgeExcluded() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libApp.so"))
        graph.addNode(makeSdk("libUnused.so"))

        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libUnused.so",
                                          realSymbolCount: 0, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libApp.so"],
                                                  protectedLibraries: [],
                                                  hasRealDependency: makeHasRealDep(graph))

        #expect(result.reachableNodes.contains("libUnused.so") == false)
    }

    @Test("Transitive removable: library reachable only through removed library is also removed")
    func cleanTransitiveRemovable() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libApp.so"))
        graph.addNode(makeSdk("libFoundation.so"))
        graph.addNode(makeSdk("libFoundationInternationalization.so"))
        graph.addNode(makeSdk("lib_FoundationICU.so"))
        graph.addNode(makeSdk("libFoundationEssentials.so"))
        graph.addNode(makeSdk("libswiftCore.so"))

        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libFoundationEssentials.so",
                                          realSymbolCount: 142, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libFoundation.so",
                                          realSymbolCount: 0, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libFoundationInternationalization.so",
                                          realSymbolCount: 0, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libFoundation.so", to: "libFoundationInternationalization.so",
                                          realSymbolCount: 32, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libFoundation.so", to: "lib_FoundationICU.so",
                                          realSymbolCount: 178, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libFoundationInternationalization.so", to: "lib_FoundationICU.so",
                                          realSymbolCount: 160, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libFoundationEssentials.so", to: "libswiftCore.so",
                                          realSymbolCount: 1500, symbols: []))

        let result = DependencyGraphCleaner.clean(graph: graph,
                                                  roots: ["libApp.so"],
                                                  protectedLibraries: [],
                                                  hasRealDependency: makeHasRealDep(graph))

        #expect(result.reachableNodes.contains("libFoundation.so") == false,
                "libFoundation.so is phantom — only phantom incoming edge")
        #expect(result.reachableNodes.contains("libFoundationInternationalization.so") == false,
                "libFoundationInternationalization.so only has real edge from removed libFoundation.so")
        #expect(result.reachableNodes.contains("lib_FoundationICU.so") == false,
                "lib_FoundationICU.so only reached through removed libraries")

        #expect(result.reachableNodes.contains("libApp.so"))
        #expect(result.reachableNodes.contains("libFoundationEssentials.so"))
        #expect(result.reachableNodes.contains("libswiftCore.so"))
    }

    // MARK: - topologicalOrder

    @Test("Topological order puts dependencies before dependents")
    func topologicalOrderBasic() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libApp.so"))
        graph.addNode(makeSdk("libswiftCore.so"))
        graph.addNode(makeSdk("libFoundation.so"))

        graph.addEdge(DependencyGraphEdge(from: "libApp.so", to: "libswiftCore.so",
                                          realSymbolCount: 10, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libswiftCore.so", to: "libFoundation.so",
                                          realSymbolCount: 5, symbols: []))

        let order = graph.topologicalOrder(of: ["libApp.so", "libswiftCore.so", "libFoundation.so"],
                                           hasRealDependency: makeHasRealDep(graph))

        let foundationIdx = order.firstIndex(of: "libFoundation.so")!
        let coreIdx = order.firstIndex(of: "libswiftCore.so")!
        let appIdx = order.firstIndex(of: "libApp.so")!

        #expect(foundationIdx < coreIdx)
        #expect(coreIdx < appIdx)
    }

    @Test("Topological order skips phantom edges")
    func topologicalOrderSkipsPhantom() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libA.so"))
        graph.addNode(makeSdk("libB.so"))
        graph.addNode(makeSdk("libC.so"))

        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libB.so", realSymbolCount: 10, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libC.so", realSymbolCount: 0, symbols: []))

        let order = graph.topologicalOrder(of: ["libA.so", "libB.so", "libC.so"],
                                           hasRealDependency: makeHasRealDep(graph))

        let bIdx = order.firstIndex(of: "libB.so")!
        let aIdx = order.firstIndex(of: "libA.so")!
        #expect(bIdx < aIdx)
    }

    @Test("Topological order matches realistic Analytics graph")
    func topologicalOrderRealisticGraph() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libMyLibrary.so"))
        graph.addNode(makeBuilt("libSwiftJava.so"))
        graph.addNode(makeSdk("libswiftCore.so"))
        graph.addNode(makeSdk("libswift_Concurrency.so"))
        graph.addNode(makeSdk("libFoundationEssentials.so"))
        graph.addNode(makeSdk("libdispatch.so"))
        graph.addNode(makeSdk("libBlocksRuntime.so"))

        graph.addEdge(DependencyGraphEdge(from: "libMyLibrary.so", to: "libswiftCore.so",
                                          realSymbolCount: 100, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libMyLibrary.so", to: "libswift_Concurrency.so",
                                          realSymbolCount: 50, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libMyLibrary.so", to: "libFoundationEssentials.so",
                                          realSymbolCount: 30, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libMyLibrary.so", to: "libSwiftJava.so",
                                          realSymbolCount: 10, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libswift_Concurrency.so", to: "libswiftCore.so",
                                          realSymbolCount: 80, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libFoundationEssentials.so", to: "libswiftCore.so",
                                          realSymbolCount: 60, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libFoundationEssentials.so", to: "libswift_Concurrency.so",
                                          realSymbolCount: 20, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libdispatch.so", to: "libBlocksRuntime.so",
                                          realSymbolCount: 15, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libswiftCore.so", to: "libdispatch.so",
                                          realSymbolCount: 40, symbols: []))

        let allNames: Set<String> = Set(graph.nodes.keys)
        let order = graph.topologicalOrder(of: allNames,
                                           hasRealDependency: makeHasRealDep(graph))

        func indexOf(_ name: String) -> Int { order.firstIndex(of: name)! }

        #expect(indexOf("libBlocksRuntime.so") < indexOf("libdispatch.so"))
        #expect(indexOf("libdispatch.so") < indexOf("libswiftCore.so"))
        #expect(indexOf("libswiftCore.so") < indexOf("libswift_Concurrency.so"))
        #expect(indexOf("libswift_Concurrency.so") < indexOf("libFoundationEssentials.so"))
        #expect(indexOf("libswiftCore.so") < indexOf("libMyLibrary.so"))
        #expect(indexOf("libSwiftJava.so") < indexOf("libMyLibrary.so"))
        #expect(indexOf("libFoundationEssentials.so") < indexOf("libMyLibrary.so"))
    }

    @Test("Topological order only includes subset nodes")
    func topologicalOrderSubset() {
        var graph = DependencyGraph()
        graph.addNode(makeBuilt("libA.so"))
        graph.addNode(makeSdk("libB.so"))
        graph.addNode(makeSdk("libC.so"))

        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libB.so", realSymbolCount: 10, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libA.so", to: "libC.so", realSymbolCount: 5, symbols: []))

        let order = graph.topologicalOrder(of: ["libA.so", "libB.so"],
                                           hasRealDependency: makeHasRealDep(graph))

        #expect(order.count == 2)
        #expect(order.contains("libC.so") == false)
        #expect(order.first == "libB.so")
        #expect(order.last == "libA.so")
    }
}

// MARK: - Private

private extension DependencyGraphTests {
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
