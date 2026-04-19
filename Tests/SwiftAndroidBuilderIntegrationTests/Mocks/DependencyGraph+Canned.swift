// DependencyGraph+Canned.swift

import Foundation

@testable import DependencyGraph

extension DependencyGraph {

    /// PetShop: two products, standard SDK deps, Foundation only via phantom edge.
    /// Graph cleaner should remove libFoundation.so (phantom from PetAnalytics).
    static func petShopPhantomFoundation(buildFolder: URL) -> DependencyGraph {
        var graph = DependencyGraph()
        graph.addNode(DependencyGraphNode(name: "libPetAnalytics.so",
                                           url: buildFolder.appending(path: "libPetAnalytics.so"),
                                           source: .built, size: 4096))
        graph.addNode(DependencyGraphNode(name: "libPetPayments.so",
                                           url: buildFolder.appending(path: "libPetPayments.so"),
                                           source: .built, size: 2048))
        graph.addNode(DependencyGraphNode(name: "libswiftCore.so",
                                           url: buildFolder.appending(path: "libswiftCore.so"),
                                           source: .sdk, size: 8192))
        graph.addNode(DependencyGraphNode(name: "libFoundation.so",
                                           url: buildFolder.appending(path: "libFoundation.so"),
                                           source: .sdk, size: 6000))
        graph.addNode(DependencyGraphNode(name: "libdispatch.so",
                                           url: buildFolder.appending(path: "libdispatch.so"),
                                           source: .sdk, size: 1024))
        graph.addNode(DependencyGraphNode(name: "libBlocksRuntime.so",
                                           url: buildFolder.appending(path: "libBlocksRuntime.so"),
                                           source: .sdk, size: 512))

        // Real edges
        graph.addEdge(DependencyGraphEdge(from: "libPetAnalytics.so", to: "libswiftCore.so",
                                           realSymbolCount: 100, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libPetPayments.so", to: "libswiftCore.so",
                                           realSymbolCount: 80, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libswiftCore.so", to: "libdispatch.so",
                                           realSymbolCount: 40, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libdispatch.so", to: "libBlocksRuntime.so",
                                           realSymbolCount: 15, symbols: []))
        // Phantom edge — should be cleaned
        graph.addEdge(DependencyGraphEdge(from: "libPetAnalytics.so", to: "libFoundation.so",
                                           realSymbolCount: 0, symbols: []))

        return graph
    }

    /// Analytics: single product with REAL symbol dependencies on Foundation libraries.
    /// Used to test that --exclude all throws when Foundation is genuinely used.
    static func analyticsRealFoundation(buildFolder: URL) -> DependencyGraph {
        var graph = DependencyGraph()
        graph.addNode(DependencyGraphNode(name: "libSwiftLibraryAndroid.so",
                                           url: buildFolder.appending(path: "libSwiftLibraryAndroid.so"),
                                           source: .built, size: 4096))
        graph.addNode(DependencyGraphNode(name: "libswiftCore.so",
                                           url: buildFolder.appending(path: "libswiftCore.so"),
                                           source: .sdk, size: 8192))
        graph.addNode(DependencyGraphNode(name: "libFoundation.so",
                                           url: buildFolder.appending(path: "libFoundation.so"),
                                           source: .sdk, size: 6000))
        graph.addNode(DependencyGraphNode(name: "lib_FoundationICU.so",
                                           url: buildFolder.appending(path: "lib_FoundationICU.so"),
                                           source: .sdk, size: 3000))
        graph.addNode(DependencyGraphNode(name: "libdispatch.so",
                                           url: buildFolder.appending(path: "libdispatch.so"),
                                           source: .sdk, size: 1024))
        graph.addNode(DependencyGraphNode(name: "libBlocksRuntime.so",
                                           url: buildFolder.appending(path: "libBlocksRuntime.so"),
                                           source: .sdk, size: 512))

        // Real edges — product genuinely uses Foundation symbols
        graph.addEdge(DependencyGraphEdge(from: "libSwiftLibraryAndroid.so", to: "libswiftCore.so",
                                           realSymbolCount: 100, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libSwiftLibraryAndroid.so", to: "libFoundation.so",
                                           realSymbolCount: 3,
                                           symbols: ["$s10Foundation4DateVMn",
                                                     "$s10Foundation3URLVMn",
                                                     "$s10Foundation10URLRequestVMn"]))
        graph.addEdge(DependencyGraphEdge(from: "libFoundation.so", to: "lib_FoundationICU.so",
                                           realSymbolCount: 178,
                                           symbols: ["$s14_FoundationICU1a",
                                                     "$s14_FoundationICU1b"]))
        graph.addEdge(DependencyGraphEdge(from: "libswiftCore.so", to: "libdispatch.so",
                                           realSymbolCount: 40, symbols: []))
        graph.addEdge(DependencyGraphEdge(from: "libdispatch.so", to: "libBlocksRuntime.so",
                                           realSymbolCount: 15, symbols: []))

        return graph
    }
}
