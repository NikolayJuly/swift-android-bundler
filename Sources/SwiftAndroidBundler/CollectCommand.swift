// CollectCommand.swift

import ArgumentParser
import DependencyCollector
import EnvironmentSetup
import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import LoggingExtension
import SharedStructs

struct CollectCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(commandName: "collect",
                                                     abstract: "Collect .so dependencies for a pre-built Android binary and copy them to a destination folder")

    @Argument(help: "Path to the binary to collect dependencies for (.xctest, .so, or executable).")
    var binaryPath: String

    @Option(name: .long,
            help: "Destination folder to copy collected .so files into.")
    var destination: String

    @Option(name: .long,
            help: "Target architecture: arm64, arm7, x86, x86_64 (default: arm64)")
    var arch: String = "arm64"

    @Option(name: .long,
            help: "Android API level (default: 28)")
    var apiLevel: Int = 28

    @Option(name: .long,
            help: "Full target triplet (e.g. aarch64-unknown-linux-android28). Alternative to --arch + --api-level.")
    var triplet: String?

    @Option(name: .long,
            help: "Swift version (e.g. 6.3). Used to select the Android SDK. If not set, uses the latest installed.")
    var swiftVersion: String?

    @Option(name: .long,
            help: "Additional folder to search for built .so files. Defaults to parent directory of the binary.")
    var buildFolder: String?

    @Flag(name: .shortAndLong,
          help: "Enable verbose logging.")
    var verbose = false

    // MARK: - AsyncParsableCommand

    func run() async throws {
        if triplet != nil && arch != "arm64" {
            throw ValidationError("Cannot use --triplet together with --arch. Use one or the other.")
        }
        if triplet != nil && apiLevel != 28 {
            throw ValidationError("Cannot use --triplet together with --api-level. Use one or the other.")
        }

        var logger = Logger(label: "CollectDeps", factory: { _ in ConsoleLogger() })
        if verbose {
            logger.logLevel = .debug
        }
        let fileSystemService: FileSystemService = FileManager.default

        try await EnvironmentValidation.validatePatchelf(logger: logger)

        let binaryURL = URL(filePath: binaryPath, directoryHint: .notDirectory)
        guard fileSystemService.fileExists(at: binaryURL) else {
            throw SimpleError("Binary not found at \(binaryPath)")
        }
        logger.info("Binary: \(binaryPath)")

        // Discover Swift SDK
        let discovery = SwiftSDKDiscovery(shellExecutor: AsyncShellExecutor(),
                                          fileSystemService: fileSystemService,
                                          logger: logger)

        let discovered: DiscoveredSwiftSDK
        if let triplet {
            discovered = try await discovery.discover(version: swiftVersion,
                                                       triplet: triplet)
        } else {
            guard let resolvedArch = AndroidArch.fromUserFriendlyName(arch) else {
                throw ValidationError("Unknown architecture '\(arch)'. Available: arm64, arm7, x86, x86_64")
            }
            discovered = try await discovery.discover(version: swiftVersion,
                                                       arch: resolvedArch,
                                                       apiLevel: apiLevel)
        }

        let (resolvedArch, resolvedApiLevel) = try AndroidArch.parse(triplet: discovered.triplet)
        logger.info("Target: \(resolvedArch.userFriendlyName), API level \(resolvedApiLevel)")

        let swiftSdk = SwiftForAndroidSDK(sysrootFolder: discovered.sdkRootPath,
                                           swiftResourcesFolder: discovered.swiftResourcesPath,
                                           resolvedTriplet: discovered.triplet,
                                           apiLevel: resolvedApiLevel)

        let buildFolderURL: URL
        if let buildFolder {
            buildFolderURL = URL(filePath: buildFolder, directoryHint: .isDirectory)
        } else {
            buildFolderURL = binaryURL.deletingLastPathComponent()
        }

        guard fileSystemService.folderExists(at: buildFolderURL) else {
            throw SimpleError("Build folder not found at \(buildFolderURL.fileSystemPath)")
        }
        logger.info("Build folder: \(buildFolderURL.fileSystemPath)")

        logger.info("Starting dependency collection...")
        let collector = DependencyCollector(swiftSdk: swiftSdk,
                                            fileSystemService: fileSystemService,
                                            logger: logger)
        let pipeline = CollectAndCopyDependencies(collector: collector,
                                                   fileSystemService: fileSystemService,
                                                   logger: logger)
        try await pipeline.run(binaryURL: binaryURL,
                               buildFolderURL: buildFolderURL,
                               destinationURL: URL(filePath: destination, directoryHint: .isDirectory),
                               arch: resolvedArch)
    }
}
