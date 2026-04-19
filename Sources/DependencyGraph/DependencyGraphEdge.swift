// DependencyGraphEdge.swift
package struct DependencyGraphEdge: Sendable {
    package let from: String
    package let to: String
    package let realSymbolCount: Int
    /// Actual symbol names from the intersection (may be truncated to save memory).
    package let symbols: [String]

    package var isPhantom: Bool {
        realSymbolCount == 0
    }
}
