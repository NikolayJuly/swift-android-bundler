// DependencyCollector.swift
import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import LoggingExtension
import SharedStructs

package struct SharedObjectFile: CustomStringConvertible {
    package let url: URL
    package let size: Int64

    package var description: String {
        let sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .memory)
        return "\(url.lastPathComponent): \(sizeString)"
    }
}

package struct DependencyCollector: DependencyCollecting, Sendable {
    /// - parameter swiftSdkPath: path like '~/Library/org.swift.swiftpm/swift-sdks/swift-6.1.2-RELEASE-android-24-0.1.artifactbundle/swift-6.1.2-release-android-24-sdk/'. Inside we expect one folder 'sysroot' or its name variation
    package init(swiftSdk: SwiftForAndroidSDK,
                 fileSystemService: FileSystemService,
                 shellExecutor: any ShellExecuting = AsyncShellExecutor(),
                 logger: Logger) {
        self.swiftSdk = swiftSdk
        self.fileSystemService = fileSystemService
        self.shellExecutor = shellExecutor
        self.logger = logger
    }

    /// - returns: list of paths to all needed `.so` files, which need to be copied with given binary at `binaryPath`
    package func collect(for binaryPath: String,
                         fromBuildFolder: URL,
                         arch: AndroidArch) async throws -> [SharedObjectFile] {
        // Pass real logger to shell commands in verbose mode, silent otherwise
        let shellLogger = logger.logLevel <= .debug ? logger : Logger.silent

        let swiftLibsFolder = swiftSdk.swiftLibsFolder()
        let sdkRootLibsFolder = swiftSdk.sdkRootLibsFolder(for: arch)
        let systemLibsFolder = swiftSdk.systemLibsFolder(for: arch)

        logger.info("Scanning SDK libraries...")
        let swiftLibs: [URL] = try fileSystemService.categorizedFolderContent(at: swiftLibsFolder).files
        let sdkRootLibs: [URL] = try fileSystemService.categorizedFolderContent(at: sdkRootLibsFolder).files
            .filter { $0.pathExtension == "so" }
        let systemLibs: [URL] = try fileSystemService.categorizedFolderContent(at: systemLibsFolder).files
        let buildFolderLibs: [URL] = try fileSystemService.categorizedFolderContent(at: fromBuildFolder).files
            .filter { $0.pathExtension == "so" }

        var knownLibsByName: [String: URL] = [:]
        for lib in swiftLibs {
            knownLibsByName[lib.lastPathComponent] = lib
        }
        for lib in sdkRootLibs {
            knownLibsByName[lib.lastPathComponent] = lib
        }
        for lib in buildFolderLibs {
            knownLibsByName[lib.lastPathComponent] = lib
        }

        let systemLibNames = Set(systemLibs.map(\.lastPathComponent))
        logger.info("Library index: \(knownLibsByName.count) known, \(systemLibNames.count) system, \(buildFolderLibs.count) from build folder")

        var foundDependencies: [String: URL] = [:]

        var queueToCheck: Set<String> = [binaryPath]

        let whileLoopLimiter = WhileLoopLimiter(limit: 250)
        var iterationCount = 0

        while whileLoopLimiter.startNextLoop(), let currentPathToCheck = queueToCheck.first {
            queueToCheck.remove(currentPathToCheck)
            iterationCount += 1

            let filename = URL(filePath: currentPathToCheck).lastPathComponent
            logger.debug("[\(iterationCount)] patchelf --print-needed \(filename)")

            let dependenciesOutput = try await shellExecutor.execute(
                ["patchelf", "--print-needed", currentPathToCheck], logger: shellLogger)

            let neededLibsNames: [String] = dependenciesOutput
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            for neededLibName in neededLibsNames {
                guard systemLibNames.contains(neededLibName) == false else {
                    continue
                }

                guard let libUrl = knownLibsByName[neededLibName] else {
                    throw SimpleError("We found unknown dependency - \(neededLibName)")
                }

                guard foundDependencies[neededLibName] == nil else {
                    continue
                }

                foundDependencies[neededLibName] = libUrl

                queueToCheck.insert(libUrl.fileSystemPath)
            }
        }

        if whileLoopLimiter.didDrainLimit {
            fatalError("Looks like we stuck in infinite loop while collecting dependencies.")
        }

        logger.info("BFS completed: \(foundDependencies.count) dependencies found in \(iterationCount) iterations")

        let sizedDependencies = try foundDependencies.values.map { url in
            let size = try fileSystemService.fileSize(at: url)
            return SharedObjectFile(url: url, size: size)
        }

        var reportString = "Dependencies for \(URL(filePath: binaryPath).lastPathComponent):\n"
        var totalSize: Int64 = 0
        for dependency in sizedDependencies {
            totalSize += dependency.size
            reportString += "  \(dependency)\n"
        }

        let formattedTotalSize = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .memory)
        reportString += "Total: \(formattedTotalSize)"

        logger.info("\(reportString)")

        return sizedDependencies
    }

    // MARK: Private

    private let swiftSdk: SwiftForAndroidSDK
    private let fileSystemService: FileSystemService
    private let shellExecutor: any ShellExecuting
    private let logger: Logger
}
