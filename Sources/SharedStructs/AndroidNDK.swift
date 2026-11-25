// AndroidNDK.swift
import FileSystemKit
import Foundation
import FoundationExtension

public struct AndroidNDK: Sendable {
    public init(ndkFolder: URL) {
        self.ndkFolder = ndkFolder
    }

    public var folderUrl: URL {
        ndkFolder
    }

    public var llvmNmUrl: URL {
        ndkFolder.appending(path: "toolchains/llvm/prebuilt/\(Self.hostPlatform)/bin/llvm-nm",
                            directoryHint: .notDirectory)
    }

    public var llvmStripUrl: URL {
        ndkFolder.appending(path: "toolchains/llvm/prebuilt/\(Self.hostPlatform)/bin/llvm-strip",
                            directoryHint: .notDirectory)
    }

    /// Discovers the latest NDK version inside `{androidSdkFolder}/ndk/`.
    public static func discoverLatest(in androidSdkFolder: URL,
                                      fileSystemService: FileSystemService) throws -> AndroidNDK {
        let ndkBaseFolder = androidSdkFolder.appending(path: "ndk", directoryHint: .isDirectory)
        let versions = try fileSystemService.folderContent(at: ndkBaseFolder)
        guard let latestVersion = versions.sorted().last else {
            throw SimpleError("No NDK versions found in \(ndkBaseFolder.fileSystemPath)")
        }
        let ndkFolder = ndkBaseFolder.appending(path: latestVersion, directoryHint: .isDirectory)
        return AndroidNDK(ndkFolder: ndkFolder)
    }

    // MARK: - Private

    private let ndkFolder: URL

    private static var hostPlatform: String {
        #if os(macOS)
        "darwin-x86_64"
        #elseif os(Linux)
        "linux-x86_64"
        #else
        fatalError("Unsupported platform for NDK toolchain")
        #endif
    }
}
