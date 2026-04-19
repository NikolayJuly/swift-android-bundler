// SwiftBuilding.swift

import Foundation
import Logging
import ShellKit

package protocol SwiftBuilding: Sendable {
    func buildProduct(_ name: String,
                      packagePath: URL,
                      configuration: BuildConfiguration,
                      triplet: String,
                      extraArgs: [String],
                      swiftVersion: String) async throws
    func getBuildOutputPath(packagePath: URL,
                            configuration: BuildConfiguration,
                            triplet: String,
                            swiftVersion: String) async throws -> URL
}

// MARK: - SwiftBuilderImpl

/// Builds Swift packages for Android via swiftly + swift-sdk.
package final class SwiftBuilderImpl: SwiftBuilding {
    package init(logger: Logger) { self.logger = logger }

    // MARK: - Package

    package func buildProduct(_ name: String,
                              packagePath: URL,
                              configuration: BuildConfiguration,
                              triplet: String,
                              extraArgs: [String],
                              swiftVersion: String) async throws {
        let path = packagePath.fileSystemPath
        try await resolvePackageDependencies(packagePath: path,
                                              swiftVersion: swiftVersion,
                                              logger: logger)

        logger.info("Building \(name) for Android...")
        var cmd = ["swiftly", "run", "swift", "build",
                   "--product", name,
                   "-c", configuration.rawValue,
                   "--swift-sdk", triplet,
                   "--package-path", path]
        cmd += extraArgs
        cmd += ["+\(swiftVersion)"]
        try await AsyncShellCommand(cmd, logger: logger).execute()
    }

    package func getBuildOutputPath(packagePath: URL,
                                    configuration: BuildConfiguration,
                                    triplet: String,
                                    swiftVersion: String) async throws -> URL {
        let cmd = ["swiftly", "run", "swift", "build",
                   "-c", configuration.rawValue,
                   "--swift-sdk", triplet,
                   "--show-bin-path",
                   "--package-path", packagePath.fileSystemPath,
                   "+\(swiftVersion)"]
        let output = try await AsyncShellCommand(cmd, logger: logger).execute()
        return URL(filePath: output.trimmingCharacters(in: .whitespacesAndNewlines),
                   directoryHint: .isDirectory)
    }

    // MARK: - Private

    private let logger: Logger
}

// MARK: - HostSwiftBuilderImpl

// MARK: - Shared

private func resolvePackageDependencies(packagePath: String,
                                        swiftVersion: String,
                                        logger: Logger) async throws {
    logger.info("Resolving dependencies for \(packagePath)...")
    let cmd = ["swiftly", "run", "swift", "package", "resolve",
               "--package-path", packagePath,
               "+\(swiftVersion)"]
    do {
        try await AsyncShellCommand(cmd, logger: .silent).execute()
    } catch {
        logger.error("Failed to resolve dependencies: \(error)")
        throw error
    }
}
