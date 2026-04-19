// SwiftSDKDiscovery.swift

import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import LoggingExtension
import SharedStructs

// MARK: - Protocol

package protocol SwiftSDKDiscovering: Sendable {
    /// Discovers Swift Android SDK using explicit triplet.
    /// Validates triplet against SDK — if invalid, throws error from `swift sdk configure`.
    func discover(version: String?,
                  triplet: String) async throws -> DiscoveredSwiftSDK

    /// Discovers Swift Android SDK by resolving triplet from arch + apiLevel via swift-sdk.json.
    /// Handles eabi/non-eabi differences across SDK versions.
    func discover(version: String?,
                  arch: AndroidArch,
                  apiLevel: Int) async throws -> DiscoveredSwiftSDK
}

// MARK: - Result

package struct DiscoveredSwiftSDK: Sendable {
    /// SDK identifier from `swift sdk list` (e.g. "swift-6.3-RELEASE_android")
    package let sdkName: String
    /// Resolved Swift toolchain version (e.g. "6.3.0")
    package let resolvedSwiftVersion: String
    /// Resolved triplet (e.g. "x86_64-unknown-linux-android29")
    package let triplet: String
    /// Folder containing swift-sdk.json
    package let sdkFolder: URL
    /// SDK root path from `swift sdk configure` (sysroot)
    package let sdkRootPath: URL
    /// Swift resources path from `swift sdk configure`
    package let swiftResourcesPath: URL
}

// MARK: - Implementation

package final class SwiftSDKDiscovery: SwiftSDKDiscovering {

    package init(shellExecutor: some ShellExecuting,
                 fileSystemService: FileSystemService,
                 logger: Logger) {
        self.shellExecutor = shellExecutor
        self.fileSystemService = fileSystemService
        self.logger = logger
        self.shellLogger = logger.logLevel <= .debug ? logger : Logger.silent
    }

    // MARK: - Package

    package func discover(version: String?,
                          triplet: String) async throws -> DiscoveredSwiftSDK {
        let resolvedVersion = try await resolveVersion(explicit: version)
        let sdkName = try await findAndroidSDK(version: resolvedVersion)
        try validateVersionMatch(toolchainVersion: resolvedVersion, sdkName: sdkName)

        return try await discover(resolvedVersion: resolvedVersion,
                                   sdkName: sdkName,
                                   triplet: triplet)
    }

    package func discover(version: String?,
                          arch: AndroidArch,
                          apiLevel: Int) async throws -> DiscoveredSwiftSDK {
        let resolvedVersion = try await resolveVersion(explicit: version)
        let sdkName = try await findAndroidSDK(version: resolvedVersion)
        try validateVersionMatch(toolchainVersion: resolvedVersion, sdkName: sdkName)

        // Bootstrap: use aarch64 to find swift-sdk.json, then resolve actual triplet
        let bootstrapTriplet = "\(AndroidArch.arm64.swiftTarget)\(apiLevel)"
        logger.info("Bootstrap: querying SDK config with \(bootstrapTriplet) to locate swift-sdk.json...")

        let (bootstrapRootPath, _) = try await querySDKConfiguration(sdkName: sdkName,
                                                                      triplet: bootstrapTriplet)
        let sdkFolder = try findSDKFolder(from: bootstrapRootPath, sdkName: sdkName)

        // Parse swift-sdk.json to find exact triplet for requested arch
        let sdkConfig = try SwiftSDKConfig.parse(from: sdkFolder,
                                                  fileSystemService: fileSystemService)
        let apiLevelSuffix = "\(apiLevel)"
        let matchingEntry = sdkConfig.targetTriples.first { key, _ in
            key.hasPrefix(arch.swiftArch) && key.hasSuffix(apiLevelSuffix)
        }

        guard let (resolvedTriplet, _) = matchingEntry else {
            let available = sdkConfig.targetTriples.keys.sorted().joined(separator: ", ")
            throw SimpleError("No triplet matching arch '\(arch.userFriendlyName)' and API level \(apiLevel) in swift-sdk.json. Available: \(available)")
        }

        logger.info("Resolved triplet from swift-sdk.json: \(resolvedTriplet)")

        return try await discover(resolvedVersion: resolvedVersion,
                                   sdkName: sdkName,
                                   triplet: resolvedTriplet)
    }

    // MARK: - Private

    private let shellExecutor: any ShellExecuting
    private let fileSystemService: FileSystemService
    private let logger: Logger
    private let shellLogger: Logger

    /// Core discovery: everything resolved, just query and return.
    private func discover(resolvedVersion: String,
                           sdkName: String,
                           triplet: String) async throws -> DiscoveredSwiftSDK {
        let (sdkRootPath, swiftResourcesPath) = try await querySDKConfiguration(sdkName: sdkName,
                                                                                  triplet: triplet)
        let sdkFolder = try findSDKFolder(from: sdkRootPath, sdkName: sdkName)

        logger.info("Discovery complete: \(sdkName), toolchain \(resolvedVersion), triplet \(triplet)")

        return DiscoveredSwiftSDK(sdkName: sdkName,
                                  resolvedSwiftVersion: resolvedVersion,
                                  triplet: triplet,
                                  sdkFolder: sdkFolder,
                                  sdkRootPath: sdkRootPath,
                                  swiftResourcesPath: swiftResourcesPath)
    }

    private func resolveVersion(explicit: String?) async throws -> String {
        if let explicit {
            logger.info("Using explicit Swift version: \(explicit)")
            return explicit
        }

        logger.info("Discovering installed Swift toolchains...")
        let output = try await shellExecutor.execute(["swiftly", "list"],
                                                      logger: shellLogger)
        let versions = output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("Swift ") else {
                    return nil
                }
                return trimmed
                    .dropFirst(6)
                    .split(separator: " ")
                    .first
                    .map(String.init)
            }

        guard let latest = versions.first else {
            throw SimpleError("No Swift toolchains found via swiftly. Install one with: swiftly install latest")
        }

        logger.info("Installed toolchains: \(versions.joined(separator: ", "))")
        logger.info("Using latest: \(latest)")
        return latest
    }

    private func findAndroidSDK(version: String) async throws -> String {
        logger.info("Discovering installed Swift SDKs...")
        let listOutput = try await shellExecutor.execute(["swiftly", "run", "swift", "sdk", "list"],
                                                          logger: shellLogger)
        let allSDKNames = listOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let androidSDKs = allSDKNames.filter { $0.lowercased().contains("android") }

        guard androidSDKs.isEmpty == false else {
            throw SimpleError("No Android Swift SDKs found. Install one with: swift sdk install <url>")
        }

        logger.info("Found Android SDKs: \(androidSDKs.joined(separator: ", "))")

        let sdkName = try Self.selectAndroidSDK(from: androidSDKs, version: version)
        logger.info("Selected: \(sdkName)")
        return sdkName
    }

    private func validateVersionMatch(toolchainVersion: String,
                                       sdkName: String) throws {
        guard let sdkVersion = Self.extractVersion(from: sdkName) else {
            logger.warning("Could not extract version from SDK name '\(sdkName)', skipping version check")
            return
        }

        let toolchainSoftwareVersion = SoftwareVersion(toolchainVersion)
        guard let toolchainSoftwareVersion else {
            logger.warning("Could not parse toolchain version '\(toolchainVersion)', skipping version check")
            return
        }

        if toolchainSoftwareVersion == sdkVersion {
            logger.info("Toolchain \(toolchainVersion) matches SDK \(sdkName)")
        } else {
            throw SimpleError("Toolchain version \(toolchainVersion) does not match SDK version (\(sdkName)). "
                            + "Swift requires exact version match between toolchain and SDK.")
        }
    }

    private func querySDKConfiguration(sdkName: String,
                                        triplet: String) async throws -> (sdkRootPath: URL, swiftResourcesPath: URL) {
        logger.info("Querying SDK configuration for triplet \(triplet)...")
        let configCommand = ["swiftly", "run", "swift", "sdk", "configure", "--show-configuration", sdkName, triplet]
        let configOutput = try await shellExecutor.execute(configCommand, logger: shellLogger)

        let (rootPath, resourcesPath) = try Self.parseSDKConfiguration(configOutput)
        logger.info("SDK root: \(rootPath)")
        logger.info("Swift resources: \(resourcesPath)")

        return (URL(filePath: rootPath, directoryHint: .isDirectory),
                URL(filePath: resourcesPath, directoryHint: .isDirectory))
    }

    private func findSDKFolder(from sdkRootPath: URL,
                                sdkName: String) throws -> URL {
        var folder = sdkRootPath
        while folder.fileSystemPath != "/" {
            let candidate = folder.appending(path: "swift-sdk.json", directoryHint: .notDirectory)
            if fileSystemService.fileExists(at: candidate) {
                logger.info("Found swift-sdk.json at \(folder.fileSystemPath)")
                return folder
            }
            folder = folder.deletingLastPathComponent()
        }

        throw SimpleError("Could not find swift-sdk.json for SDK '\(sdkName)'. sdkRootPath was: \(sdkRootPath.fileSystemPath)")
    }
}

// MARK: - Pure functions

extension SwiftSDKDiscovery {

    /// Selects an Android SDK from a list by matching version.
    static func selectAndroidSDK(from androidSDKs: [String],
                                  version: String) throws -> String {
        let requestedVersion = SoftwareVersion(version)
        guard let requestedVersion else {
            throw SimpleError("Invalid SDK version format: '\(version)'. Expected format: 6.3 or 6.3.0")
        }

        let matching = androidSDKs.filter { name in
            guard let extracted = extractVersion(from: name) else {
                return false
            }
            return extracted == requestedVersion
        }

        guard let found = matching.first else {
            throw SimpleError("No Android SDK matching version '\(version)'. Available: \(androidSDKs.joined(separator: ", "))")
        }

        guard matching.count == 1 else {
            throw SimpleError("Multiple Android SDKs match version '\(version)': \(matching.joined(separator: ", "))")
        }

        return found
    }

    /// Extracts version from SDK name like "swift-6.3-RELEASE_android" -> SoftwareVersion("6.3")
    static func extractVersion(from sdkName: String) -> SoftwareVersion? {
        let segments = sdkName.split { $0 == "-" || $0 == "_" }.map(String.init)
        for segment in segments {
            if segment.first?.isNumber == true,
               let version = SoftwareVersion(segment) {
                return version
            }
        }
        return nil
    }

    /// Parses key-value output from `swift sdk configure --show-configuration`.
    static func parseSDKConfiguration(_ output: String) throws -> (sdkRootPath: String, swiftResourcesPath: String) {
        var sdkRootPath: String?
        var swiftResourcesPath: String?

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colonIndex = trimmed.firstIndex(of: ":") else {
                continue
            }

            let key = trimmed[trimmed.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)

            guard value != "not set" else {
                continue
            }

            switch key {
            case "sdkRootPath": sdkRootPath = value
            case "swiftResourcesPath": swiftResourcesPath = value
            default: break
            }
        }

        guard let sdkRootPath else {
            throw SimpleError("sdkRootPath not found in SDK configuration output")
        }

        guard let swiftResourcesPath else {
            throw SimpleError("swiftResourcesPath not found in SDK configuration output")
        }

        return (sdkRootPath, swiftResourcesPath)
    }
}
