// BuildCommand.swift

import ArgumentParser
import EnvironmentSetup
import FileSystemKit
import Foundation
import Logging
import LoggingExtension
import SharedStructs
import SwiftAndroidBuilder

extension StripMode: ExpressibleByArgument {}
extension BuildConfiguration: ExpressibleByArgument {}
extension ExcludeMode: ExpressibleByArgument {}

struct BuildCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(commandName: "build",
                                                     abstract: "Build Swift products for Android from source packages")

    @Option(name: .long, help: "Swift library product name to build (can be repeated)")
    var product: [String]

    @Option(name: .long, help: "Path to Swift package directory (can be repeated)")
    var swiftPackage: [String]

    @Option(name: .long, help: "Path to destination folder for all .so files")
    var destination: String

    @Option(name: .long, help: "Target architecture: arm64, arm7, x86, x86_64 (can be repeated, default: arm64)")
    var arch: [String] = ["arm64"]

    @Option(name: .long, help: "Android API level (default: 28)")
    var apiLevel: Int = 28

    @Option(name: .long, help: "Full target triplet (e.g. aarch64-unknown-linux-android28). Alternative to --arch + --api-level.")
    var triplet: String?

    @Option(name: .long, help: "Swift version (e.g. 6.3). Used to select both toolchain and Android SDK. If not set, uses the latest installed.")
    var swiftVersion: String?

    @Option(name: [.customLong("configuration")], help: "Build configuration: release (default) or debug")
    var buildConfiguration: BuildConfiguration = .release

    @Option(name: .long, help: "Exclusion mode: none (default), full-foundation, foundation-networking, all")
    var exclude: ExcludeMode = .none

    @Option(name: .long, help: "Strip mode for .so files: none (default), debug, all")
    var strip: StripMode = .none

    @Option(name: .long, help: "Path to Android SDK folder (needed for NDK tools: llvm-nm, llvm-strip)")
    var androidSdkPath: String = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Android/sdk", directoryHint: .isDirectory).fileSystemPath

    @Option(name: .long, help: "Path to directory where swift-libs-manifest.json will be written. If not specified, no manifest is generated.")
    var manifestDestination: String?

    @Option(name: .long, help: "Firebase app ID for uploading debug symbols to Crashlytics")
    var firebaseAppId: String?

    @Option(name: .long, help: "Path to folder for archived debug symbols")
    var symbolsDestination: String?

    @Argument(parsing: .captureForPassthrough, help: "Extra arguments for the underlying command")
    var extraArgs: [String] = []

    func run() async throws {
        if triplet != nil && arch != ["arm64"] {
            throw ValidationError("Cannot use --triplet together with --arch. Use one or the other.")
        }

        let logger = Logger(label: "DefaultLogger", factory: { _ in ConsoleLogger() })

        let architectures: [AndroidArch]
        if let triplet {
            let (resolvedArch, _) = try AndroidArch.parse(triplet: triplet)
            architectures = [resolvedArch]
        } else {
            architectures = try arch.map { name in
                guard let resolved = AndroidArch.fromUserFriendlyName(name) else {
                    throw ValidationError("Unknown architecture '\(name)'. Available: arm64, arm7, x86, x86_64")
                }
                return resolved
            }
        }

        let request = BuildRequest(products: product,
                                    swiftPackages: swiftPackage.map { URL(filePath: $0, directoryHint: .isDirectory) })

        let fileSystemService: FileSystemService = FileManager.default

        // Validate tools
        try await EnvironmentValidation.validateSwiftly(logger: logger)
        try await EnvironmentValidation.validatePatchelf(logger: logger)
        if firebaseAppId != nil {
            try await EnvironmentValidation.validateFirebase(logger: logger)
        }

        // Discover Swift SDK
        let discovery = SwiftSDKDiscovery(shellExecutor: AsyncShellExecutor(),
                                          fileSystemService: fileSystemService,
                                          logger: logger)

        // Build uses first arch as bootstrap for discovery, pipeline resolves per-arch from swift-sdk.json
        let bootstrapArch = architectures[0]
        let resolvedApiLevel: Int

        let discovered: DiscoveredSwiftSDK
        if let triplet {
            let (_, parsedApiLevel) = try AndroidArch.parse(triplet: triplet)
            resolvedApiLevel = parsedApiLevel
            discovered = try await discovery.discover(version: swiftVersion,
                                                       triplet: triplet)
        } else {
            resolvedApiLevel = apiLevel
            discovered = try await discovery.discover(version: swiftVersion,
                                                       arch: bootstrapArch,
                                                       apiLevel: apiLevel)
        }

        let resolvedSwiftVersion = discovered.resolvedSwiftVersion
        let resolvedSdkPath = discovered.sdkFolder

        let environment = BuildEnvironment(architectures: architectures,
                                            apiLevel: resolvedApiLevel,
                                            swiftSdkPath: resolvedSdkPath,
                                            swiftVersion: resolvedSwiftVersion,
                                            androidSdkPath: URL(filePath: androidSdkPath, directoryHint: .isDirectory),
                                            configuration: buildConfiguration)

        let manifestDir = manifestDestination.map { URL(filePath: $0, directoryHint: .isDirectory) }
        let symbolsDir = symbolsDestination.map { URL(filePath: $0, directoryHint: .isDirectory) }
        let output = BuildOutput(destination: URL(filePath: destination, directoryHint: .isDirectory),
                                  manifestDestination: manifestDir,
                                  excludeMode: exclude,
                                  stripMode: strip,
                                  firebaseAppId: firebaseAppId,
                                  symbolsDestination: symbolsDir,
                                  extraArgs: extraArgs)

        let androidSdkUrl = URL(filePath: androidSdkPath, directoryHint: .isDirectory)
        let ndk = try AndroidNDK.discoverLatest(in: androidSdkUrl, fileSystemService: fileSystemService)
        try EnvironmentValidation.validateLlvmNm(ndk, logger: logger)

        let pipeline = FromConfigPipeline(request: request,
                                         environment: environment,
                                         output: output,
                                         resolvedSwiftVersion: resolvedSwiftVersion,
                                         ndk: ndk,
                                         packageDumper: PackageDumperImpl(),
                                         builder: SwiftBuilderImpl(logger: logger),
                                         graphing: DependencyGrapherImpl(),
                                         postProcessor: PostProcessorImpl(),
                                         fileSystemService: fileSystemService,
                                         logger: logger)
        try await pipeline.run()
    }
}
