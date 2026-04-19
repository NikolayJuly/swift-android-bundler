// DependencyGraphing.swift

import DependencyGraph
import FileSystemKit
import Foundation
import Logging
import SharedStructs

package protocol DependencyGraphing: Sendable {
    func buildGraph(soFiles: [URL],
                    buildFolders: [URL],
                    swiftSdk: SwiftForAndroidSDK,
                    arch: AndroidArch,
                    ndk: AndroidNDK,
                    fileSystemService: FileSystemService,
                    logger: Logger) async throws -> DependencyGraph
    func stripPhantomEdges(_ entries: [PatchEntry],
                           destination: URL,
                           logger: Logger) async throws -> [PatchEntry]
}

// MARK: - DependencyGrapherImpl

package struct DependencyGrapherImpl: DependencyGraphing {
    package init() {}

    package func buildGraph(soFiles: [URL],
                            buildFolders: [URL],
                            swiftSdk: SwiftForAndroidSDK,
                            arch: AndroidArch,
                            ndk: AndroidNDK,
                            fileSystemService: FileSystemService,
                            logger: Logger) async throws -> DependencyGraph {
        try await DependencyGraphBuilder.build(for: soFiles,
                                                buildFolders: buildFolders,
                                                swiftSdk: swiftSdk,
                                                arch: arch,
                                                ndk: ndk,
                                                fileSystemService: fileSystemService,
                                                logger: logger)
    }

    package func stripPhantomEdges(_ entries: [PatchEntry],
                                   destination: URL,
                                   logger: Logger) async throws -> [PatchEntry] {
        try await PhantomEdgeStripper.strip(entries,
                                             destinationFolder: destination,
                                             logger: logger)
    }
}
