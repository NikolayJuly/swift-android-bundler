// DependencyGraphCleaner.swift
package struct PatchEntry: Sendable {
    /// File in destination that needs patching (the dependent .so)
    package let file: String
    /// NEEDED entry to remove from that file
    package let removeNeeded: String
}

package struct CleanResult: Sendable {
    /// Nodes that should be copied to destination
    package let reachableNodes: Set<String>
    /// Nodes that were removed (not needed)
    package let removedNodes: Set<String>
    /// NEEDED entries to strip from copied files via patchelf
    package let patchEntries: [PatchEntry]
}

/// Analyzes a dependency graph and determines the minimal set of libraries needed.
/// Separates policy (what is a real dependency) from the graph model.
package final class DependencyGraphCleaner {
    private init() {}

    /// Cleans the dependency graph: finds reachable nodes via BFS over real edges,
    /// determines which nodes to remove, and which NEEDED entries to patch.
    ///
    /// - Parameters:
    ///   - graph: The full dependency graph
    ///   - roots: Root libraries (built products)
    ///   - protectedLibraries: Libraries that must never be removed (e.g. JNI-loaded)
    ///   - hasRealDependency: `(from, to) -> Bool` — whether `from` truly depends on `to`
    /// - Returns: `CleanResult` with reachable nodes, removed nodes, and patch entries
    package static func clean(graph: DependencyGraph,
                              roots: Set<String>,
                              protectedLibraries: Set<String>,
                              hasRealDependency: (String, String) -> Bool) -> CleanResult {
        // BFS from roots + protected libraries, following only real edges
        var visited = Set<String>()
        let protectedRoots = protectedLibraries.filter { graph.nodes[$0] != nil }
        var queue = Array(roots) + Array(protectedRoots)

        while let current = queue.first {
            queue.removeFirst()
            guard visited.contains(current) == false else { continue }
            visited.insert(current)

            for edge in graph.edges where edge.from == current {
                guard hasRealDependency(edge.from, edge.to) else { continue }
                if visited.contains(edge.to) == false {
                    queue.append(edge.to)
                }
            }
        }

        let removedNodes = Set(graph.nodes.keys).subtracting(visited)

        // Patch entries: for each reachable file, collect edges to removed nodes
        var patchEntries: [PatchEntry] = []
        for edge in graph.edges {
            guard visited.contains(edge.from),
                  removedNodes.contains(edge.to) else { continue }
            patchEntries.append(PatchEntry(file: edge.from, removeNeeded: edge.to))
        }

        return CleanResult(reachableNodes: visited,
                           removedNodes: removedNodes,
                           patchEntries: patchEntries)
    }
}
