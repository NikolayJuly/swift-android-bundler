// TestCollectCommand.swift

import AndroidTestKit
import ArgumentParser
import DependencyCollector
import EnvironmentSetup
import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import LoggingExtension
import SharedStructs
import SwiftAndroidBuilder

struct TestCollectCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(commandName: "collect",
                                                     abstract: "Collect the test runners of a built package, with every .so they load, into one folder")

    @Option(name: .long,
            help: "Path to the Swift package whose tests were built with `swift build --build-tests`.")
    var packagePath: String

    @Option(name: .long,
            help: "The --scratch-path the tests were built with. Default: the package's .build.")
    var scratchPath: String?

    @Option(name: .long,
            help: "Destination folder for the runners and their .so files.")
    var destination: String

    @Option(name: .customLong("test-target"),
            help: "Test target to collect (can be repeated). Default: every test target of the package.")
    var testTargets: [String] = []

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
            help: "Swift version, patch included (e.g. 6.4.3). If not set, uses the latest installed.")
    var swiftVersion: String?

    @Option(name: .long,
            help: "Path to Android SDK folder, for the NDK when ANDROID_NDK_HOME is not set. Default: $ANDROID_HOME, else ~/Library/Android/sdk.")
    var androidSdkPath: String = ProcessInfo.processInfo.environment["ANDROID_HOME"]
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Android/sdk", directoryHint: .isDirectory).fileSystemPath

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

        var logger = Logger(label: "TestCollect", factory: { _ in ConsoleLogger() })
        if verbose {
            logger.logLevel = .debug
        }
        let fileSystemService: FileSystemService = FileManager.default

        try await EnvironmentValidation.validateSwiftly(logger: logger)
        try await EnvironmentValidation.validatePatchelf(logger: logger)

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

        let swiftSdk = SwiftForAndroidSDK(sysrootFolder: discovered.sdkRootPath,
                                          swiftResourcesFolder: discovered.swiftResourcesPath,
                                          resolvedTriplet: discovered.triplet,
                                          apiLevel: resolvedApiLevel)
        let dependencyCollector = DependencyCollector(swiftSdk: swiftSdk,
                                                      fileSystemService: fileSystemService,
                                                      logger: logger)
        let copier = CollectAndCopyDependencies(collector: dependencyCollector,
                                                fileSystemService: fileSystemService,
                                                logger: logger)

        let androidSdkUrl = URL(filePath: androidSdkPath, directoryHint: .isDirectory)
        let ndk = try AndroidNDK.discoverLatest(in: androidSdkUrl, fileSystemService: fileSystemService)
        let builder = SwiftBuilderImpl(sdkName: discovered.sdkName,
                                       ndk: ndk,
                                       logger: logger)

        let collector = TestsCollector(packageDumper: PackageDumperImpl(),
                                       builder: builder,
                                       copier: copier,
                                       fileSystemService: fileSystemService,
                                       logger: logger)
        let packageUrl = URL(filePath: packagePath, directoryHint: .isDirectory)
        let scratchUrl = scratchPath.map { URL(filePath: $0, directoryHint: .isDirectory) }
        let destinationUrl = URL(filePath: destination, directoryHint: .isDirectory)
        try await collector.collect(packagePath: packageUrl,
                                    scratchPath: scratchUrl,
                                    testTargets: testTargets,
                                    triplet: discovered.triplet,
                                    swiftVersion: discovered.resolvedSwiftVersion,
                                    arch: resolvedArch,
                                    destination: destinationUrl)
    }
}
