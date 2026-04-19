// SwiftForAndroidSDKTests.swift

import FileSystemKit
import Foundation
import SharedStructs
import Testing

@Suite("SwiftForAndroidSDK")
struct SwiftForAndroidSDKTests {

    private let rootUrl = URL(filePath: "/")
    private let appRoot = URL(filePath: "/app")

    @Test("Resolves triplet from 6.3 SDK (armv7 without eabi)")
    func resolvedTriplet63() throws {
        let fs = InMemoryFileSystemService(rootUrl: rootUrl, appRootContainer: appRoot)
        let sdkFolder = URL(filePath: "/sdk")
        try fs.createEmptyFolder(at: sdkFolder)

        let json = """
        {
          "schemaVersion": "4.0",
          "targetTriples": {
            "aarch64-unknown-linux-android28": {
              "sdkRootPath": "ndk-sysroot",
              "swiftResourcesPath": "swift-resources/usr/lib/swift-aarch64"
            },
            "armv7-unknown-linux-android28": {
              "sdkRootPath": "ndk-sysroot",
              "swiftResourcesPath": "swift-resources/usr/lib/swift-armv7"
            }
          }
        }
        """
        try fs.write(data: Data(json.utf8),
                     to: sdkFolder.appendingPathComponent("swift-sdk.json", isDirectory: false))

        // Create required folders
        try fs.createAllSubfolders(upTo: sdkFolder.appendingPathComponent("swift-resources/usr/lib/swift-armv7/android",
                                                                           isDirectory: true),
                                   in: sdkFolder)
        try fs.createAllSubfolders(upTo: sdkFolder.appendingPathComponent("ndk-sysroot/usr/lib/arm-linux-androideabi/28",
                                                                           isDirectory: true),
                                   in: sdkFolder)

        let sdk = try SwiftForAndroidSDK(sdkFolder: sdkFolder,
                                          arch: .arm7,
                                          apiLevel: 28,
                                          fileSystemService: fs)

        #expect(sdk.resolvedTriplet == "armv7-unknown-linux-android28")
    }

    @Test("Resolves triplet from 6.2.3 SDK (armv7 with eabi)")
    func resolvedTriplet623() throws {
        let fs = InMemoryFileSystemService(rootUrl: rootUrl, appRootContainer: appRoot)
        let sdkFolder = URL(filePath: "/sdk")
        try fs.createEmptyFolder(at: sdkFolder)

        let json = """
        {
          "schemaVersion": "4.0",
          "targetTriples": {
            "aarch64-unknown-linux-android28": {
              "sdkRootPath": "android-sysroot",
              "swiftResourcesPath": "android-sysroot/usr/lib/swift"
            },
            "armv7-unknown-linux-androideabi28": {
              "sdkRootPath": "android-sysroot",
              "swiftResourcesPath": "android-sysroot/usr/lib/swift"
            }
          }
        }
        """
        try fs.write(data: Data(json.utf8),
                     to: sdkFolder.appendingPathComponent("swift-sdk.json", isDirectory: false))

        try fs.createAllSubfolders(upTo: sdkFolder.appendingPathComponent("android-sysroot/usr/lib/swift/android",
                                                                           isDirectory: true),
                                   in: sdkFolder)
        try fs.createAllSubfolders(upTo: sdkFolder.appendingPathComponent("android-sysroot/usr/lib/arm-linux-androideabi/28",
                                                                           isDirectory: true),
                                   in: sdkFolder)

        let sdk = try SwiftForAndroidSDK(sdkFolder: sdkFolder,
                                          arch: .arm7,
                                          apiLevel: 28,
                                          fileSystemService: fs)

        #expect(sdk.resolvedTriplet == "armv7-unknown-linux-androideabi28")
    }
}
