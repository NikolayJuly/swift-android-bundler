// TestsCollector.swift

import DependencyCollector
import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import SharedStructs
import SwiftAndroidBuilder

/// Collects a package's test runners with every .so they load into one folder.
/// swiftbuild links each test target into its own `<Target>-test-runner` + `<Target>.so`, nothing joins them.
package final class TestsCollector {

    package init(packageDumper: some PackageDumping,
                 builder: some SwiftBuilding,
                 copier: CollectAndCopyDependencies,
                 fileSystemService: FileSystemService,
                 logger: Logger) {
        self.packageDumper = packageDumper
        self.builder = builder
        self.copier = copier
        self.fileSystemService = fileSystemService
        self.logger = logger
    }

    // MARK: - Package

    /// - Parameter testTargets: the targets to collect; empty means every test target of the package.
    /// - Throws: when a test target has no runner in the build folder.
    package func collect(packagePath: URL,
                         scratchPath: URL?,
                         testTargets: [String],
                         triplet: String,
                         swiftVersion: String,
                         arch: AndroidArch,
                         destination: URL) async throws {
        let targets: [String]
        if testTargets.isEmpty {
            targets = try await packageDumper.dumpTestTargets(at: packagePath)
        } else {
            targets = testTargets
        }
        guard targets.isEmpty == false else {
            throw SimpleError("No test targets in \(packagePath.fileSystemPath)")
        }
        logger.info("Test targets: \(targets.joined(separator: ", "))")

        let buildFolder = try await builder.getBuildOutputPath(packagePath: packagePath,
                                                               scratchPath: scratchPath,
                                                               configuration: .debug,
                                                               triplet: triplet,
                                                               swiftVersion: swiftVersion)
        logger.info("Build folder: \(buildFolder.fileSystemPath)")

        // One after another: every runner copies the same runtime .so files into the same folder.
        for target in targets {
            let runnerURL = buildFolder.appending(path: TestRunnerName.runnerName(for: target),
                                                  directoryHint: .notDirectory)
            guard fileSystemService.fileExists(at: runnerURL) else {
                throw SimpleError("Test runner not found at \(runnerURL.fileSystemPath)")
            }
            try await copier.run(binaryURL: runnerURL,
                                 buildFolderURL: buildFolder,
                                 destinationURL: destination,
                                 arch: arch)
        }
    }

    // MARK: - Private

    private let packageDumper: any PackageDumping
    private let builder: any SwiftBuilding
    private let copier: CollectAndCopyDependencies
    private let fileSystemService: FileSystemService
    private let logger: Logger
}
