// SwiftForAndroidSDK.swift

import FileSystemKit
import Foundation
import FoundationExtension

public struct SwiftForAndroidSDK: Sendable {
    public init(sdkFolder: URL,
                arch: AndroidArch,
                apiLevel: Int,
                fileSystemService: FileSystemService) throws {
        let config = try SwiftSDKConfig.parse(from: sdkFolder, fileSystemService: fileSystemService)
        try self.init(sdkFolder: sdkFolder, config: config, arch: arch, apiLevel: apiLevel)
    }

    package init(sdkFolder: URL,
                 config: SwiftSDKConfig,
                 arch: AndroidArch,
                 apiLevel: Int) throws {

        // Find matching triplet: starts with arch.swiftArch, ends with apiLevel
        let apiLevelSuffix = "\(apiLevel)"
        let matchingEntry = config.targetTriples.first { key, _ in
            key.hasPrefix(arch.swiftArch) && key.hasSuffix(apiLevelSuffix)
        }

        guard let (triplet, tripleConfig) = matchingEntry else {
            let available = config.targetTriples.keys.sorted().joined(separator: ", ")
            throw SimpleError("No triplet matching arch '\(arch.swiftArch)' and API level \(apiLevel) in swift-sdk.json. Available: \(available)")
        }

        self.resolvedTriplet = triplet
        self.sysrootFolder = sdkFolder.appending(path: tripleConfig.sdkRootPath, directoryHint: .isDirectory)

        guard let resourcesPath = tripleConfig.swiftResourcesPath else {
            throw SimpleError("swiftResourcesPath not found for triplet '\(triplet)' in swift-sdk.json")
        }
        self.swiftResourcesFolder = sdkFolder.appending(path: resourcesPath, directoryHint: .isDirectory)

        self.apiLevel = apiLevelSuffix
    }

    /// Creates SDK from absolute paths (e.g. from `swift sdk configure --show-configuration`).
    public init(sysrootFolder: URL,
                swiftResourcesFolder: URL,
                resolvedTriplet: String,
                apiLevel: Int) {
        self.sysrootFolder = sysrootFolder
        self.swiftResourcesFolder = swiftResourcesFolder
        self.resolvedTriplet = resolvedTriplet
        self.apiLevel = "\(apiLevel)"
    }

    // MARK: - Public

    /// Triplet resolved from swift-sdk.json, used for `swift build --swift-sdk`
    public let resolvedTriplet: String

    /// Swift runtime .so files (libswiftCore.so, libFoundation.so, etc.)
    public func swiftLibsFolder() -> URL {
        // TODO: As an alternative, we could scan the entire SDK folder for .so files
        // and determine their target architecture by parsing ELF headers,
        // instead of relying on swift-sdk.json path conventions.
        swiftResourcesFolder.appending(path: "android", directoryHint: .isDirectory)
    }

    /// SDK root libs (e.g. libc++_shared.so) — sdkRootPath/usr/lib/{arch}/ without API level
    public func sdkRootLibsFolder(for arch: AndroidArch) -> URL {
        sysrootFolder.appending(path: "usr/lib/\(arch.ndkLibArchName)",
                                directoryHint: .isDirectory)
    }

    /// System libs (NDK stubs: libc, libm, liblog, etc.) — sdkRootPath/usr/lib/{arch}/{apiLevel}/
    public func systemLibsFolder(for arch: AndroidArch) -> URL {
        sysrootFolder.appending(path: "usr/lib/\(arch.ndkLibArchName)/\(apiLevel)",
                                directoryHint: .isDirectory)
    }

    // MARK: - Private

    private let sysrootFolder: URL
    private let swiftResourcesFolder: URL
    private let apiLevel: String
}

// MARK: - swift-sdk.json model

package struct SwiftSDKConfig: Decodable, Sendable {
    package let targetTriples: [String: TripleConfig]

    package struct TripleConfig: Decodable, Sendable {
        package let sdkRootPath: String
        package let swiftResourcesPath: String?
    }

    package static func parse(from sdkFolder: URL,
                              fileSystemService: FileSystemService) throws -> SwiftSDKConfig {
        let configUrl = sdkFolder.appending(path: "swift-sdk.json", directoryHint: .notDirectory)
        let configData = try fileSystemService.fileContent(at: configUrl)
        return try JSONDecoder().decode(SwiftSDKConfig.self, from: configData)
    }
}
