// SymbolAnalyzer.swift
import Foundation
import Logging
import LoggingExtension
import SharedStructs
import ShellKit
import WorkPoolDraining

package enum SymbolAnalyzer {
    /// Analyzes all edges in the graph by cross-referencing undefined and defined dynamic symbols.
    /// Caches llvm-nm results per .so file to avoid redundant invocations.
    /// Returns edges with actual symbol counts filled in.
    package static func analyzeEdges(in graph: DependencyGraph,
                                     ndk: AndroidNDK,
                                     logger: Logger) async throws -> [DependencyGraphEdge] {
        let pendingEdges = graph.edges

        guard pendingEdges.isEmpty == false else {
            return []
        }

        // Collect unique .so files we need to analyze
        var fromUrls: [String: URL] = [:]
        var toUrls: [String: URL] = [:]

        for edge in pendingEdges {
            if let node = graph.nodes[edge.from] {
                fromUrls[edge.from] = node.url
            }
            if let node = graph.nodes[edge.to] {
                toUrls[edge.to] = node.url
            }
        }

        let allUniqueUrls = Set(fromUrls.values).union(toUrls.values)
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        logger.info("Analyzing symbols for \(pendingEdges.count) edges across \(allUniqueUrls.count) .so files (\(coreCount) parallel)...")

        // Run llvm-nm in parallel for all unique .so files, collecting both undefined and defined symbols
        let urlArray = Array(allUniqueUrls)
        let drainer = StaticAsyncWorkPoolDrainer(stack: urlArray,
                                                  maxConcurrentOperationCount: coreCount) { url in
            let undefined = await undefinedDynamicSymbols(at: url, ndk: ndk)
            let defined = await definedDynamicSymbols(at: url, ndk: ndk)
            return (url, undefined, defined)
        }

        var undefinedCache: [URL: Set<String>] = [:]
        var definedCache: [URL: Set<String>] = [:]

        for try await (url, undefined, defined) in drainer {
            undefinedCache[url] = undefined
            definedCache[url] = defined
        }

        // Compute intersections for each edge
        var analyzedEdges: [DependencyGraphEdge] = []

        for edge in pendingEdges {
            guard let fromUrl = fromUrls[edge.from],
                  let toUrl = toUrls[edge.to],
                  let undefined = undefinedCache[fromUrl],
                  let defined = definedCache[toUrl] else {
                // Conservative: if we can't analyze, treat as non-phantom
                analyzedEdges.append(DependencyGraphEdge(from: edge.from,
                                                          to: edge.to,
                                                          realSymbolCount: -1,
                                                          symbols: []))
                continue
            }

            let intersection = undefined.intersection(defined)
            let symbolCount = intersection.count

            if symbolCount > 0 {
                logger.info("\(edge.from) -> \(edge.to): \(symbolCount) symbols")
            } else {
                logger.info("\(edge.from) -> \(edge.to): 0 symbols (phantom)")
            }

            analyzedEdges.append(DependencyGraphEdge(from: edge.from,
                                                      to: edge.to,
                                                      realSymbolCount: symbolCount,
                                                      symbols: Array(intersection).sorted()))
        }

        return analyzedEdges
    }
    /// Parses llvm-nm output lines like:
    /// ```
    ///                  U _symbolName
    /// 0000000000001234 T _symbolName
    /// ```
    /// Extracts the symbol name (last whitespace-separated column).
    package static func parseNmOutput(_ output: String) -> Set<String> {
        var symbols = Set<String>()
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            // Symbol name is the last column
            if let lastSpace = trimmed.lastIndex(of: " ") {
                let symbol = String(trimmed[trimmed.index(after: lastSpace)...])
                symbols.insert(symbol)
            }
        }
        return symbols
    }
}

// MARK: - Private

private extension SymbolAnalyzer {
    /// Runs `llvm-nm -D -u <path>` and returns the set of undefined dynamic symbol names.
    static func undefinedDynamicSymbols(at url: URL, ndk: AndroidNDK) async -> Set<String> {
        do {
            let output = try await AsyncShellCommand(ndk.llvmNmUrl.fileSystemPath, "-D", "-u", url.fileSystemPath,
                                                      logger: .silent).execute()
            return parseNmOutput(output)
        } catch {
            return []
        }
    }

    /// Runs `llvm-nm -D --defined-only <path>` and returns the set of defined/exported symbol names.
    static func definedDynamicSymbols(at url: URL, ndk: AndroidNDK) async -> Set<String> {
        do {
            let output = try await AsyncShellCommand(ndk.llvmNmUrl.fileSystemPath, "-D", "--defined-only", url.fileSystemPath,
                                                      logger: .silent).execute()
            return parseNmOutput(output)
        } catch {
            return []
        }
    }
}
