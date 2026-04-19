// InMemoryFileSystemService+TestSetup.swift

import FileSystemKit
import Foundation

extension InMemoryFileSystemService {

    /// Creates the minimal folder structure for a mock Swift Android SDK at `/sdk/swift-android`
    /// with swift-sdk.json, NDK sysroot, and Swift runtime lib directories for aarch64 / API 28.
    func setupSwiftAndroidSDK() throws {
        let sdkBase = URL(filePath: "/sdk/swift-android")
        try createEmptyFolder(at: URL(filePath: "/sdk"))
        try createEmptyFolder(at: sdkBase)

        let sdkConfigJson = """
        {
          "schemaVersion": "4.0",
          "targetTriples": {
            "aarch64-unknown-linux-android28": {
              "sdkRootPath": "ndk-sysroot",
              "swiftResourcesPath": "swift-resources/usr/lib/swift-aarch64"
            }
          }
        }
        """
        let sdkConfigUrl = sdkBase.appendingPathComponent("swift-sdk.json", isDirectory: false)
        try write(data: Data(sdkConfigJson.utf8), to: sdkConfigUrl)

        let systemLibsDir = sdkBase.appendingPathComponent("ndk-sysroot/usr/lib/aarch64-linux-android/28",
                                                            isDirectory: true)
        try createAllSubfolders(upTo: systemLibsDir, in: sdkBase)

        let swiftLibsDir = sdkBase.appendingPathComponent("swift-resources/usr/lib/swift-aarch64/android",
                                                           isDirectory: true)
        try createAllSubfolders(upTo: swiftLibsDir, in: sdkBase)
    }

    /// Creates shared folders needed by the pipeline: /tmp, symbols archive base, build folder chain.
    func setupPipelineInfrastructure(buildFolder: URL) throws {
        try createEmptyFolder(at: URL(filePath: "/tmp"))

        try createFolderChain(at: appSupportFolderUrl)

        // Build folder chain
        var current = buildFolder
        var ancestors: [URL] = []
        while current.path() != "/" && current.path().isEmpty == false {
            ancestors.append(current)
            current = current.deletingLastPathComponent()
        }
        for ancestor in ancestors.reversed() {
            if folderExists(at: ancestor) == false {
                try createEmptyFolder(at: ancestor)
            }
        }
    }

    /// Creates the folder chain from root up to the given URL.
    func createFolderChain(at url: URL) throws {
        var components: [String] = []
        var current = url
        while current.path() != "/" && current.path().isEmpty == false {
            components.append(current.lastPathComponent)
            current = current.deletingLastPathComponent()
        }

        var building = URL(filePath: "/")
        for component in components.reversed() {
            building = building.appendingPathComponent(component, isDirectory: true)
            if folderExists(at: building) == false {
                try createEmptyFolder(at: building)
            }
        }
    }
}
