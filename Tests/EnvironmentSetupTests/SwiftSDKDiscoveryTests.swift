// SwiftSDKDiscoveryTests.swift

import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import SharedStructs
import Testing

@testable import EnvironmentSetup

@Suite("SwiftSDKDiscovery")
struct SwiftSDKDiscoveryTests {

    private let rootUrl = URL(filePath: "/")
    private let appRoot = URL(filePath: "/app")

    // MARK: - discover(version:triplet:)

    /// Auto-discovery with triplet: picks latest toolchain,
    /// finds matching Android SDK, queries config for specific triplet.
    @Test("Triplet-based discovery resolves latest toolchain and matching SDK")
    func tripletDiscovery() async throws {
        let (shell, fs) = try makeEnvironment(
            toolchainVersions: ["6.3.0", "6.2.3"],
            androidSDKs: ["swift-6.3-RELEASE_android"],
            configTriplet: "aarch64-unknown-linux-android28",
            sdkConfigOutput: sdkConfigOutput63Aarch64,
            sdkJsonContent: sdkJson63
        )

        let discovery = SwiftSDKDiscovery(shellExecutor: shell,
                                           fileSystemService: fs,
                                           logger: silentLogger)
        let result = try await discovery.discover(version: nil,
                                                    triplet: "aarch64-unknown-linux-android28")

        #expect(result.sdkName == "swift-6.3-RELEASE_android")
        #expect(result.resolvedSwiftVersion == "6.3.0")
        #expect(result.triplet == "aarch64-unknown-linux-android28")
        #expect(result.swiftResourcesPath.fileSystemPath.contains("swift-aarch64"))
    }

    /// Explicit version with triplet selects correct SDK.
    @Test("Explicit version with triplet selects matching SDK")
    func explicitVersionWithTriplet() async throws {
        let (shell, fs) = try makeEnvironment(
            toolchainVersions: ["6.3.0", "6.2.3"],
            androidSDKs: ["swift-6.3-RELEASE_android", "swift-6.2.3-RELEASE-android-24-0.1"],
            selectedSDKName: "swift-6.2.3-RELEASE-android-24-0.1",
            configTriplet: "aarch64-unknown-linux-android28",
            sdkConfigOutput: sdkConfigOutput623,
            sdkJsonContent: sdkJson623
        )

        let discovery = SwiftSDKDiscovery(shellExecutor: shell,
                                           fileSystemService: fs,
                                           logger: silentLogger)
        let result = try await discovery.discover(version: "6.2.3",
                                                    triplet: "aarch64-unknown-linux-android28")

        #expect(result.sdkName == "swift-6.2.3-RELEASE-android-24-0.1")
        #expect(result.resolvedSwiftVersion == "6.2.3")
    }

    // MARK: - discover(version:arch:apiLevel:)

    /// Arch-based discovery for x86_64: resolves correct triplet from swift-sdk.json,
    /// returns x86_64-specific paths (NOT aarch64).
    @Test("Arch-based discovery returns correct architecture paths")
    func archDiscoveryX86() async throws {
        let (shell, fs) = try makeEnvironment(
            toolchainVersions: ["6.3.0"],
            androidSDKs: ["swift-6.3-RELEASE_android"],
            configTriplet: "aarch64-unknown-linux-android28",
            sdkConfigOutput: sdkConfigOutput63Aarch64,
            sdkJsonContent: sdkJson63
        )

        // Also register the x86_64 config response
        shell.register(pattern: "sdk configure.*x86_64-unknown-linux-android28",
                       output: sdkConfigOutput63X86_64)

        let discovery = SwiftSDKDiscovery(shellExecutor: shell,
                                           fileSystemService: fs,
                                           logger: silentLogger)
        let result = try await discovery.discover(version: nil,
                                                    arch: .x86_64,
                                                    apiLevel: 28)

        #expect(result.triplet == "x86_64-unknown-linux-android28")
        #expect(result.swiftResourcesPath.fileSystemPath.contains("swift-x86_64"))
        #expect(result.swiftResourcesPath.fileSystemPath.contains("swift-aarch64") == false)
    }

    /// Arch-based discovery for arm7 with eabi (SDK 6.2.3): resolves triplet with eabi suffix.
    @Test("Arch-based discovery resolves arm7 eabi triplet for SDK 6.2.3")
    func archDiscoveryArm7Eabi() async throws {
        let (shell, fs) = try makeEnvironment(
            toolchainVersions: ["6.2.3"],
            androidSDKs: ["swift-6.2.3-RELEASE-android-24-0.1"],
            configTriplet: "aarch64-unknown-linux-android28",
            sdkConfigOutput: sdkConfigOutput623,
            sdkJsonContent: sdkJson623
        )

        shell.register(pattern: "sdk configure.*androideabi28",
                       output: """
                           sdkRootPath: /sdk/swift-android-623/android-sysroot
                           swiftResourcesPath: /sdk/swift-android-623/android-sysroot/usr/lib/swift
                           swiftStaticResourcesPath: not set
                           includeSearchPaths: not set
                           librarySearchPaths: not set
                           """)

        let discovery = SwiftSDKDiscovery(shellExecutor: shell,
                                           fileSystemService: fs,
                                           logger: silentLogger)
        let result = try await discovery.discover(version: "6.2.3",
                                                    arch: .arm7,
                                                    apiLevel: 28)

        #expect(result.triplet == "armv7-unknown-linux-androideabi28")
    }

    /// Arch-based discovery for arm7 without eabi (SDK 6.3): resolves triplet without eabi.
    @Test("Arch-based discovery resolves arm7 non-eabi triplet for SDK 6.3")
    func archDiscoveryArm7NoEabi() async throws {
        let (shell, fs) = try makeEnvironment(
            toolchainVersions: ["6.3.0"],
            androidSDKs: ["swift-6.3-RELEASE_android"],
            configTriplet: "aarch64-unknown-linux-android28",
            sdkConfigOutput: sdkConfigOutput63Aarch64,
            sdkJsonContent: sdkJson63
        )

        shell.register(pattern: "sdk configure.*armv7-unknown-linux-android28",
                       output: """
                           sdkRootPath: /sdk/swift-android/ndk-sysroot
                           swiftResourcesPath: /sdk/swift-android/swift-resources/usr/lib/swift-armv7
                           swiftStaticResourcesPath: not set
                           includeSearchPaths: not set
                           librarySearchPaths: not set
                           """)

        let discovery = SwiftSDKDiscovery(shellExecutor: shell,
                                           fileSystemService: fs,
                                           logger: silentLogger)
        let result = try await discovery.discover(version: nil,
                                                    arch: .arm7,
                                                    apiLevel: 28)

        #expect(result.triplet == "armv7-unknown-linux-android28")
    }

    /// Arch not found in swift-sdk.json — throws error.
    @Test("Throws when arch not found in swift-sdk.json")
    func archNotFoundThrows() async throws {
        let (shell, fs) = try makeEnvironment(
            toolchainVersions: ["6.3.0"],
            androidSDKs: ["swift-6.3-RELEASE_android"],
            configTriplet: "aarch64-unknown-linux-android28",
            sdkConfigOutput: sdkConfigOutput63Aarch64,
            sdkJsonContent: sdkJson63
        )

        let discovery = SwiftSDKDiscovery(shellExecutor: shell,
                                           fileSystemService: fs,
                                           logger: silentLogger)

        // swift-sdk.json has API 28 entries, but we request API 99
        await #expect(throws: Error.self) {
            try await discovery.discover(version: nil,
                                          arch: .x86_64,
                                          apiLevel: 99)
        }
    }

    // MARK: - Error cases

    /// Toolchain version doesn't match any installed Android SDK — throws error.
    @Test("Throws when toolchain version has no matching SDK")
    func versionMismatchThrows() async throws {
        let shell = MockShellExecutor()
        let fs = InMemoryFileSystemService(rootUrl: rootUrl, appRootContainer: appRoot)

        shell.outputByCommand["swiftly list"] = """
            Installed release toolchains
            ----------------------------
            Swift 6.3.0
            """
        shell.outputByCommand["swiftly run swift sdk list"] = "swift-6.2.3-RELEASE-android-24-0.1"

        let discovery = SwiftSDKDiscovery(shellExecutor: shell,
                                           fileSystemService: fs,
                                           logger: silentLogger)

        await #expect(throws: Error.self) {
            try await discovery.discover(version: nil,
                                          triplet: "aarch64-unknown-linux-android28")
        }
    }

    /// No Android SDKs installed at all — throws error.
    @Test("Throws when no Android SDKs installed")
    func noAndroidSDKThrows() async throws {
        let shell = MockShellExecutor()
        let fs = InMemoryFileSystemService(rootUrl: rootUrl, appRootContainer: appRoot)

        shell.outputByCommand["swiftly list"] = """
            Installed release toolchains
            ----------------------------
            Swift 6.3.0
            """
        shell.outputByCommand["swiftly run swift sdk list"] = "ubuntu_jammy_aarch64"

        let discovery = SwiftSDKDiscovery(shellExecutor: shell,
                                           fileSystemService: fs,
                                           logger: silentLogger)

        await #expect(throws: Error.self) {
            try await discovery.discover(version: nil,
                                          triplet: "aarch64-unknown-linux-android28")
        }
    }

    /// SDK config returns valid paths but swift-sdk.json doesn't exist — throws error.
    @Test("Throws when swift-sdk.json not found")
    func swiftSdkJsonNotFoundThrows() async throws {
        let shell = MockShellExecutor()
        let fs = InMemoryFileSystemService(rootUrl: rootUrl, appRootContainer: appRoot)

        shell.outputByCommand["swiftly list"] = """
            Installed release toolchains
            ----------------------------
            Swift 6.3.0
            """
        shell.outputByCommand["swiftly run swift sdk list"] = "swift-6.3-RELEASE_android"
        shell.register(pattern: "sdk configure.*aarch64-unknown-linux-android28",
                       output: sdkConfigOutput63Aarch64)

        // Create sdkRootPath folder but NO swift-sdk.json anywhere
        try fs.createAllSubfolders(upTo: URL(filePath: "/sdk/swift-android/ndk-sysroot"),
                                    in: rootUrl)

        let discovery = SwiftSDKDiscovery(shellExecutor: shell,
                                           fileSystemService: fs,
                                           logger: silentLogger)

        await #expect(throws: Error.self) {
            try await discovery.discover(version: nil,
                                          triplet: "aarch64-unknown-linux-android28")
        }
    }

    // MARK: - Static helpers

    /// selectAndroidSDK filters by version correctly.
    @Test("selectAndroidSDK picks matching version")
    func selectByVersion() throws {
        let sdks = ["swift-6.2.3-RELEASE-android-24-0.1", "swift-6.3-RELEASE_android"]
        let selected = try SwiftSDKDiscovery.selectAndroidSDK(from: sdks, version: "6.2.3")
        #expect(selected == "swift-6.2.3-RELEASE-android-24-0.1")
    }

    /// selectAndroidSDK throws when no match.
    @Test("selectAndroidSDK throws when version not found")
    func selectNoMatchThrows() {
        let sdks = ["swift-6.3-RELEASE_android"]
        #expect(throws: Error.self) {
            try SwiftSDKDiscovery.selectAndroidSDK(from: sdks, version: "6.2")
        }
    }

    /// selectAndroidSDK throws on ambiguous match.
    @Test("selectAndroidSDK throws on multiple matches")
    func selectAmbiguousThrows() {
        let sdks = ["swift-6.3-RELEASE_android", "swift-6.3-RELEASE_android-v2"]
        #expect(throws: Error.self) {
            try SwiftSDKDiscovery.selectAndroidSDK(from: sdks, version: "6.3")
        }
    }

    /// extractVersion handles various SDK name formats.
    @Test("extractVersion parses SDK names")
    func extractVersionFormats() {
        #expect(SwiftSDKDiscovery.extractVersion(from: "swift-6.3-RELEASE_android") == SoftwareVersion("6.3"))
        #expect(SwiftSDKDiscovery.extractVersion(from: "swift-6.2.3-RELEASE-android-24-0.1") == SoftwareVersion("6.2.3"))
        #expect(SwiftSDKDiscovery.extractVersion(from: "ubuntu_jammy_aarch64") == nil)
    }

    /// parseSDKConfiguration extracts paths from CLI output.
    @Test("parseSDKConfiguration parses paths correctly")
    func parseConfiguration() throws {
        let (root, resources) = try SwiftSDKDiscovery.parseSDKConfiguration(sdkConfigOutput63Aarch64)
        #expect(root == "/sdk/swift-android/ndk-sysroot")
        #expect(resources == "/sdk/swift-android/swift-resources/usr/lib/swift-aarch64")
    }

    /// parseSDKConfiguration throws when keys are missing.
    @Test("parseSDKConfiguration throws on missing keys")
    func parseConfigurationMissing() {
        #expect(throws: Error.self) {
            try SwiftSDKDiscovery.parseSDKConfiguration("includeSearchPaths: not set")
        }
    }
}

// MARK: - Private

private extension SwiftSDKDiscoveryTests {

    var silentLogger: Logger {
        var logger = Logger(label: "test")
        logger.logLevel = .critical
        return logger
    }

    // MARK: - Test data

    var sdkConfigOutput63Aarch64: String {
        """
        sdkRootPath: /sdk/swift-android/ndk-sysroot
        swiftResourcesPath: /sdk/swift-android/swift-resources/usr/lib/swift-aarch64
        swiftStaticResourcesPath: not set
        includeSearchPaths: not set
        librarySearchPaths: not set
        """
    }

    var sdkConfigOutput63X86_64: String {
        """
        sdkRootPath: /sdk/swift-android/ndk-sysroot
        swiftResourcesPath: /sdk/swift-android/swift-resources/usr/lib/swift-x86_64
        swiftStaticResourcesPath: not set
        includeSearchPaths: not set
        librarySearchPaths: not set
        """
    }

    var sdkConfigOutput623: String {
        """
        sdkRootPath: /sdk/swift-android-623/android-sysroot
        swiftResourcesPath: /sdk/swift-android-623/android-sysroot/usr/lib/swift
        swiftStaticResourcesPath: not set
        includeSearchPaths: not set
        librarySearchPaths: not set
        """
    }

    var sdkJson63: String {
        """
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
            },
            "x86_64-unknown-linux-android28": {
              "sdkRootPath": "ndk-sysroot",
              "swiftResourcesPath": "swift-resources/usr/lib/swift-x86_64"
            }
          }
        }
        """
    }

    var sdkJson623: String {
        """
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
    }

    // MARK: - Environment setup

    func makeEnvironment(toolchainVersions: [String],
                          androidSDKs: [String],
                          selectedSDKName: String? = nil,
                          configTriplet: String,
                          sdkConfigOutput: String,
                          sdkJsonContent: String) throws -> (MockShellExecutor, InMemoryFileSystemService) {
        let shell = MockShellExecutor()
        let fs = InMemoryFileSystemService(rootUrl: rootUrl, appRootContainer: appRoot)

        // swiftly list
        let toolchainLines = toolchainVersions.map { "Swift \($0)" }.joined(separator: "\n")
        shell.outputByCommand["swiftly list"] = """
            Installed release toolchains
            ----------------------------
            \(toolchainLines)
            """

        // swift sdk list
        let allSDKs = androidSDKs + ["ubuntu_jammy_aarch64"]
        shell.outputByCommand["swiftly run swift sdk list"] = allSDKs.joined(separator: "\n")

        // swift sdk configure — match by triplet suffix
        shell.register(pattern: "sdk configure.*\(configTriplet)",
                       output: sdkConfigOutput)

        // Create filesystem with swift-sdk.json
        let sdkRootPath = try SwiftSDKDiscovery.parseSDKConfiguration(sdkConfigOutput).sdkRootPath
        let sdkRootUrl = URL(filePath: sdkRootPath, directoryHint: .isDirectory)
        try fs.createAllSubfolders(upTo: sdkRootUrl, in: rootUrl)

        // swift-sdk.json is one level up from sdkRootPath
        let sdkFolder = sdkRootUrl.deletingLastPathComponent()
        let sdkJsonUrl = sdkFolder.appending(path: "swift-sdk.json", directoryHint: .notDirectory)
        try fs.write(data: Data(sdkJsonContent.utf8), to: sdkJsonUrl)

        return (shell, fs)
    }
}
