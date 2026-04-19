// DependencyGraphBuilder.swift
import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import LoggingExtension
import SharedStructs
import ShellKit

package enum DependencyGraphBuilder {
    /// Builds a full dependency graph with symbol-level analysis.
    /// 1. BFS traversal via `patchelf --print-needed` to discover the graph structure
    /// 2. Symbol analysis via `llvm-nm -D` to determine real vs phantom edges
    package static func build(for soFiles: [URL],
                              buildFolders: [URL],
                              swiftSdk: SwiftForAndroidSDK,
                              arch: AndroidArch,
                              ndk: AndroidNDK,
                              fileSystemService: FileSystemService,
                              logger: Logger) async throws -> DependencyGraph {
        let swiftLibsFolder = swiftSdk.swiftLibsFolder()
        let sdkRootLibsFolder = swiftSdk.sdkRootLibsFolder(for: arch)
        let systemLibsFolder = swiftSdk.systemLibsFolder(for: arch)

        logger.info("Swift runtime libs: \(swiftLibsFolder.fileSystemPath)")
        logger.info("SDK root libs: \(sdkRootLibsFolder.fileSystemPath)")
        logger.info("System libs: \(systemLibsFolder.fileSystemPath)")
        for folder in buildFolders {
            logger.info("Build folder: \(folder.fileSystemPath)")
        }

        let swiftLibs: [URL] = try fileSystemService.categorizedFolderContent(at: swiftLibsFolder).files
        let sdkRootLibs: [URL] = try fileSystemService.categorizedFolderContent(at: sdkRootLibsFolder).files
            .filter { $0.pathExtension == "so" }
        let systemLibs: [URL] = try fileSystemService.categorizedFolderContent(at: systemLibsFolder).files
        var buildFolderLibs: [URL] = []
        for folder in buildFolders {
            let libs = try fileSystemService.categorizedFolderContent(at: folder).files
                .filter { $0.pathExtension == "so" }
            buildFolderLibs.append(contentsOf: libs)
        }

        logger.info("Swift libs: \(swiftLibs.count), SDK root libs: \(sdkRootLibs.count), system libs: \(systemLibs.count), build .so: \(buildFolderLibs.count)")

        // Build lookup: name → (url, source)
        var knownLibs: [String: (url: URL, source: SharedObjectSource)] = [:]
        for lib in swiftLibs {
            knownLibs[lib.lastPathComponent] = (lib, .sdk)
        }
        for lib in sdkRootLibs {
            knownLibs[lib.lastPathComponent] = (lib, .sdk)
        }
        for lib in buildFolderLibs {
            knownLibs[lib.lastPathComponent] = (lib, .built)
        }

        let systemLibNames = Set(systemLibs.map(\.lastPathComponent))

        logger.info("Known libs: \(knownLibs.count), system libs (excluded): \(systemLibNames.count)")
        logger.info("Building dependency graph...")

        var graph = DependencyGraph()

        // Add root nodes (our built products)
        for soFile in soFiles {
            let size = try fileSystemService.fileSize(at: soFile)
            graph.addNode(DependencyGraphNode(name: soFile.lastPathComponent,
                                               url: soFile,
                                               source: .built,
                                               size: size))
        }

        // BFS edges (before symbol analysis — realSymbolCount will be 0 as placeholder)
        var pendingEdges: [(from: String, to: String)] = []
        var visited = Set<String>()
        var queueToCheck: [(name: String, path: String)] = soFiles.map { ($0.lastPathComponent, $0.fileSystemPath) }

        let whileLoopLimiter = WhileLoopLimiter(limit: 250)

        while whileLoopLimiter.startNextLoop(), let current = queueToCheck.first {
            queueToCheck.removeFirst()

            guard visited.contains(current.name) == false else {
                continue
            }
            visited.insert(current.name)

            let patchElfOutput = try await AsyncShellCommand("patchelf", "--print-needed", current.path,
                                                              logger: .silent).execute()
            let neededNames = patchElfOutput
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }

            if neededNames.isEmpty == false {
                logger.info("\(current.name) NEEDED: \(neededNames)")
            }

            for neededName in neededNames {
                guard systemLibNames.contains(neededName) == false else {
                    continue
                }

                guard let known = knownLibs[neededName] else {
                    throw SimpleError("Unknown dependency: \(neededName) (needed by \(current.name))")
                }

                pendingEdges.append((from: current.name, to: neededName))

                // Add node if not yet in graph
                if graph.nodes[neededName] == nil {
                    let size = try fileSystemService.fileSize(at: known.url)
                    graph.addNode(DependencyGraphNode(name: neededName,
                                                       url: known.url,
                                                       source: known.source,
                                                       size: size))
                }

                if visited.contains(neededName) == false {
                    queueToCheck.append((neededName, known.url.fileSystemPath))
                }
            }
        }

        if whileLoopLimiter.didDrainLimit {
            fatalError("Stuck in infinite loop while building dependency graph.")
        }

        // Add placeholder edges so SymbolAnalyzer can see the graph structure
        for edge in pendingEdges {
            graph.addEdge(DependencyGraphEdge(from: edge.from,
                                               to: edge.to,
                                               realSymbolCount: 0,
                                               symbols: []))
        }

        // Phase 2: Symbol analysis
        let analyzedEdges = try await SymbolAnalyzer.analyzeEdges(in: graph,
                                                                   ndk: ndk,
                                                                   logger: logger)

        // Replace placeholder edges with analyzed ones
        var result = DependencyGraph()
        for node in graph.nodes.values {
            result.addNode(node)
        }
        for edge in analyzedEdges {
            result.addEdge(edge)
        }

        return result
    }
}
