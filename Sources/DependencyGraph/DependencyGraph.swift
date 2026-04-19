// DependencyGraph.swift
import Foundation

package struct DependencyGraph: Sendable {
    package private(set) var nodes: [String: DependencyGraphNode] = [:]
    package private(set) var edges: [DependencyGraphEdge] = []

    package init() {}

    package mutating func addNode(_ node: DependencyGraphNode) {
        nodes[node.name] = node
    }

    package mutating func addEdge(_ edge: DependencyGraphEdge) {
        edges.append(edge)
    }

    /// Topological sort of the given node subset using only real edges (where `hasRealDependency` returns true).
    /// Returns names in dependency-first order (leaf dependencies first, roots last).
    /// Nodes with no dependencies among themselves are sorted alphabetically for stability.
    package func topologicalOrder(of subset: Set<String>,
                                  hasRealDependency: (String, String) -> Bool) -> [String] {
        // Build in-degree map for the subset (only real edges within the subset)
        var inDegree: [String: Int] = [:]
        for name in subset {
            inDegree[name] = 0
        }

        var adjacency: [String: [String]] = [:]
        for edge in edges where hasRealDependency(edge.from, edge.to)
                                && subset.contains(edge.from)
                                && subset.contains(edge.to) {
            adjacency[edge.to, default: []].append(edge.from)
            inDegree[edge.from, default: 0] += 1
        }

        // Kahn's algorithm — use sorted queue for deterministic output
        var queue = subset.filter { inDegree[$0] == 0 }.sorted()
        var result: [String] = []

        while queue.isEmpty == false {
            let current = queue.removeFirst()
            result.append(current)

            for dependent in (adjacency[current] ?? []).sorted() {
                inDegree[dependent, default: 0] -= 1
                if inDegree[dependent] == 0 {
                    // Insert in sorted position to maintain alphabetical tie-breaking
                    let insertIndex = queue.firstIndex(where: { $0 > dependent }) ?? queue.endIndex
                    queue.insert(dependent, at: insertIndex)
                }
            }
        }

        return result
    }
}
