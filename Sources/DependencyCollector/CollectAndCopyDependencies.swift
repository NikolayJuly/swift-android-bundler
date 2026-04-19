// CollectAndCopyDependencies.swift

import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import SharedStructs

/// Collects .so dependencies for a binary and copies them to a destination folder.
package struct CollectAndCopyDependencies {

    package init(collector: some DependencyCollecting,
                 fileSystemService: FileSystemService,
                 logger: Logger) {
        self.collector = collector
        self.fileSystemService = fileSystemService
        self.logger = logger
    }

    // MARK: - Package

    package func run(binaryURL: URL,
                     buildFolderURL: URL,
                     destinationURL: URL,
                     arch: AndroidArch) async throws {
        logger.info("Collecting dependencies for \(binaryURL.lastPathComponent) (\(arch.userFriendlyName))...")

        let dependencies = try await collector.collect(for: binaryURL.fileSystemPath,
                                                       fromBuildFolder: buildFolderURL,
                                                       arch: arch)

        try fileSystemService.createFolderIfNotExists(at: destinationURL)

        // Copy the binary itself
        logger.debug("Copying binary: \(binaryURL.lastPathComponent)")
        let binaryDest = destinationURL.appending(path: binaryURL.lastPathComponent,
                                                   directoryHint: .notDirectory)
        if fileSystemService.fileExists(at: binaryDest) {
            try fileSystemService.removeItem(at: binaryDest)
        }
        try fileSystemService.copyItem(at: binaryURL, to: binaryDest)

        let binarySize = try fileSystemService.fileSize(at: binaryURL)
        var totalSize: Int64 = binarySize

        // Copy .so dependencies
        for dep in dependencies {
            logger.debug("Copying: \(dep.url.lastPathComponent)")
            let destFile = destinationURL.appending(path: dep.url.lastPathComponent,
                                                    directoryHint: .notDirectory)
            if fileSystemService.fileExists(at: destFile) {
                try fileSystemService.removeItem(at: destFile)
            }
            try fileSystemService.copyItem(at: dep.url, to: destFile)
            totalSize += dep.size
        }

        let formattedSize = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .memory)
        logger.info("Copied \(binaryURL.lastPathComponent) + \(dependencies.count) .so files (\(formattedSize)) to \(destinationURL.fileSystemPath)")
    }

    // MARK: - Private

    private let collector: any DependencyCollecting
    private let fileSystemService: FileSystemService
    private let logger: Logger
}
