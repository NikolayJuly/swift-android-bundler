// SwiftBuilding.swift

import Foundation
import FoundationExtension
import Logging
import SharedStructs
import ShellKit

package protocol SwiftBuilding: Sendable {
    func buildProduct(_ name: String,
                      packagePath: URL,
                      configuration: BuildConfiguration,
                      triplet: String,
                      extraArgs: [String],
                      swiftVersion: String) async throws
    /// - Parameter scratchPath: the `--scratch-path` the package was built with, `nil` for the default `.build`.
    func getBuildOutputPath(packagePath: URL,
                            scratchPath: URL?,
                            configuration: BuildConfiguration,
                            triplet: String,
                            swiftVersion: String) async throws -> URL
}

// MARK: - SwiftBuilderImpl

/// Builds Swift packages for Android via swiftly + swift-sdk.
package final class SwiftBuilderImpl: SwiftBuilding {

    /// - Parameter sdkName: the discovered SDK id, e.g. `swift-6.4.3-RELEASE_android`.
    package init(sdkName: String,
                 ndk: AndroidNDK,
                 logger: Logger) {
        self.sdkName = sdkName
        self.ndk = ndk
        self.logger = logger
    }

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
        var cmd = ndkEnvironmentPrefix
        cmd += ["swiftly", "run", "swift", "build",
                "--product", name,
                "-c", configuration.rawValue]
        cmd += sdkArguments(triplet: triplet, swiftVersion: swiftVersion)
        cmd += ["--package-path", path]
        cmd += extraArgs
        cmd += ["+\(swiftVersion)"]
        try await AsyncShellCommand(cmd, logger: logger).execute()
    }

    package func getBuildOutputPath(packagePath: URL,
                                    scratchPath: URL?,
                                    configuration: BuildConfiguration,
                                    triplet: String,
                                    swiftVersion: String) async throws -> URL {
        var cmd = ndkEnvironmentPrefix
        cmd += ["swiftly", "run", "swift", "build",
                "-c", configuration.rawValue]
        cmd += sdkArguments(triplet: triplet, swiftVersion: swiftVersion)
        cmd += ["--show-bin-path",
                "--package-path", packagePath.fileSystemPath]
        if let scratchPath {
            cmd += ["--scratch-path", scratchPath.fileSystemPath]
        }
        cmd += ["+\(swiftVersion)"]
        let output = try await AsyncShellCommand(cmd, logger: logger).execute()
        return URL(filePath: output.trimmingCharacters(in: .whitespacesAndNewlines),
                   directoryHint: .isDirectory)
    }

    // MARK: - Private

    private let sdkName: String
    private let ndk: AndroidNDK
    private let logger: Logger

    /// SwiftPM before 6.4.0 ignores `--triple` next to an SDK id, so there the triple alone picks the SDK.
    private func sdkArguments(triplet: String,
                              swiftVersion: String) -> [String] {
        let version = SoftwareVersion(swiftVersion)
        let firstVersionWithTriple = SoftwareVersion(digits: [6, 4, 0])
        guard let version,
              version >= firstVersionWithTriple else {
            return ["--swift-sdk", triplet]
        }
        return ["--swift-sdk", sdkName, "--triple", triplet]
    }

    /// `swift build` 6.4 looks the NDK up itself and fails when neither variable is set.
    private var ndkEnvironmentPrefix: [String] {
        let environment = ProcessInfo.processInfo.environment
        let isNdkSet = environment["ANDROID_NDK_HOME"] != nil || environment["ANDROID_NDK_ROOT"] != nil
        guard !isNdkSet else {
            return []
        }
        return ["env", "ANDROID_NDK_HOME=\(ndk.folderUrl.fileSystemPath)"]
    }
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
