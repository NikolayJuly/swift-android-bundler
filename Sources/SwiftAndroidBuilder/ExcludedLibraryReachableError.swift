// ExcludedLibraryReachableError.swift

import Foundation

/// Thrown when libraries marked for exclusion (via `--exclude`) are still reachable
/// through real symbol dependencies in the dependency graph.
package struct ExcludedLibraryReachableError: LocalizedError {

    package struct ReachableLibrary: Sendable {
        package let name: String
        package let edges: [Edge]

        package struct Edge: Sendable {
            package let from: String
            package let symbolCount: Int
            package let symbols: [String]
        }
    }

    package let libraries: [ReachableLibrary]
    package let excludeModeName: String

    package var errorDescription: String? {
        var lines: [String] = []
        lines.append("")
        lines.append("Excluded libraries are reachable via real symbol dependencies (--exclude \(excludeModeName)):")
        lines.append("")

        for library in libraries {
            lines.append("  \(library.name)")
            for edge in library.edges {
                lines.append("    \u{2190} \(edge.from) (\(edge.symbolCount) symbols):")
                let symbolsToShow = edge.symbols.prefix(3)
                for symbol in symbolsToShow {
                    lines.append("        \(symbol)")
                }
                let remaining = edge.symbolCount - symbolsToShow.count
                if remaining > 0 {
                    lines.append("        ... and \(remaining) more")
                }
            }
            lines.append("")
        }

        lines.append("Your code uses these libraries. Either remove the usage or change --exclude mode.")
        return lines.joined(separator: "\n")
    }
}
