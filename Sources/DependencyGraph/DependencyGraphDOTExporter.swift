// DependencyGraphDOTExporter.swift
package enum DependencyGraphDOTExporter {
    package static func export(_ graph: DependencyGraph,
                               strippedEdges: [PatchEntry] = []) -> String {
        var lines: [String] = []
        lines.append("digraph dependencies {")
        lines.append("  rankdir=LR;")
        lines.append("  node [shape=box, fontname=\"Helvetica\"];")
        lines.append("  edge [fontname=\"Helvetica\", fontsize=10];")
        lines.append("")

        // Nodes grouped by source
        let builtNodes = graph.nodes.values.filter { $0.source == .built }.sorted { $0.name < $1.name }
        let sdkNodes = graph.nodes.values.filter { $0.source == .sdk }.sorted { $0.name < $1.name }

        if builtNodes.isEmpty == false {
            lines.append("  // Built products")
            for node in builtNodes {
                lines.append("  \"\(node.name)\" [style=filled, fillcolor=lightgreen];")
            }
            lines.append("")
        }

        if sdkNodes.isEmpty == false {
            lines.append("  // SDK libraries")
            for node in sdkNodes {
                lines.append("  \"\(node.name)\" [style=filled, fillcolor=lightblue];")
            }
            lines.append("")
        }

        // Active edges (non-phantom, still in graph)
        let activeEdges = graph.edges.filter { $0.isPhantom == false }.sorted { "\($0.from)->\($0.to)" < "\($1.from)->\($1.to)" }
        if activeEdges.isEmpty == false {
            lines.append("  // Active dependencies")
            for edge in activeEdges {
                lines.append("  \"\(edge.from)\" -> \"\(edge.to)\" [label=\"\(edge.realSymbolCount) symbols\"];")
            }
            lines.append("")
        }

        // Stripped phantom edges (shown as dashed red)
        let sortedStripped = strippedEdges.sorted { "\($0.file)->\($0.removeNeeded)" < "\($1.file)->\($1.removeNeeded)" }
        if sortedStripped.isEmpty == false {
            lines.append("  // Stripped (phantom) dependencies")
            for entry in sortedStripped {
                lines.append("  \"\(entry.file)\" -> \"\(entry.removeNeeded)\" [style=dashed, color=red, label=\"stripped\"];")
            }
            lines.append("")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
