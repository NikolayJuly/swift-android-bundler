// CollectAndCopyDependenciesTests.swift

import FileSystemKit
import Foundation
import Logging
import SharedStructs
import Testing

@testable import DependencyCollector

/// Integration test for the full collect-and-copy pipeline.
///
/// All production code is real: DependencyCollector BFS traversal,
/// CollectAndCopyDependencies copy logic, file system operations.
/// Only external tool (patchelf) is mocked via MockShellExecutor.
@Suite("CollectAndCopyDependencies")
struct CollectAndCopyDependenciesTests {

    /// Scenario: collect dependencies for a test binary (.xctest).
    /// The BFS traversal discovers transitive deps, skips system libs,
    /// then copies both the binary and all discovered .so files to destination.
    ///
    /// Dependency graph:
    ///   MyTests.xctest → libMyLib.so, libswiftCore.so
    ///   libMyLib.so → libswiftCore.so, libc.so (system)
    ///   libswiftCore.so → libdispatch.so, libc.so (system)
    ///   libdispatch.so → libc.so (system)
    @Test("Binary and all transitive dependencies are collected and copied")
    func fullPipelineCollectsAndCopies() async throws {
        // --- Setup file system ---

        let fs = InMemoryFileSystemService(rootUrl: URL(filePath: "/"),
                                            appRootContainer: URL(filePath: "/app"))

        // SDK structure
        let sdkRoot = URL(filePath: "/sdk")
        let sysrootFolder = URL(filePath: "/sdk/ndk-sysroot")
        let swiftResourcesFolder = URL(filePath: "/sdk/swift-resources/usr/lib/swift-aarch64")

        // Swift runtime libs
        let swiftLibsDir = swiftResourcesFolder.appending(path: "android", directoryHint: .isDirectory)
        try fs.createAllSubfolders(upTo: swiftLibsDir, in: sdkRoot)
        try fs.write(data: Data("elf-swiftCore".utf8),
                     to: swiftLibsDir.appending(path: "libswiftCore.so", directoryHint: .notDirectory))
        try fs.write(data: Data("elf-dispatch".utf8),
                     to: swiftLibsDir.appending(path: "libdispatch.so", directoryHint: .notDirectory))

        // SDK root libs (e.g. libc++_shared)
        let sdkRootLibsDir = sysrootFolder.appending(path: "usr/lib/aarch64-linux-android",
                                                       directoryHint: .isDirectory)
        try fs.createAllSubfolders(upTo: sdkRootLibsDir, in: sdkRoot)

        // System libs (stubs excluded from collection)
        let systemLibsDir = sdkRootLibsDir.appending(path: "28", directoryHint: .isDirectory)
        try fs.createAllSubfolders(upTo: systemLibsDir, in: sdkRoot)
        try fs.write(data: Data("stub-libc".utf8),
                     to: systemLibsDir.appending(path: "libc.so", directoryHint: .notDirectory))

        // Build folder with binary and built .so
        let buildFolder = URL(filePath: "/build/debug")
        try fs.createAllSubfolders(upTo: buildFolder, in: URL(filePath: "/"))

        let binaryURL = buildFolder.appending(path: "MyTests.xctest", directoryHint: .notDirectory)
        try fs.write(data: Data("elf-test-binary".utf8), to: binaryURL)

        let myLibURL = buildFolder.appending(path: "libMyLib.so", directoryHint: .notDirectory)
        try fs.write(data: Data("elf-mylib".utf8), to: myLibURL)

        // Destination
        let destination = URL(filePath: "/output/test-bundle")
        try fs.createAllSubfolders(upTo: destination, in: URL(filePath: "/"))

        // --- Setup SDK ---

        let swiftSdk = SwiftForAndroidSDK(sysrootFolder: sysrootFolder,
                                           swiftResourcesFolder: swiftResourcesFolder,
                                           resolvedTriplet: "aarch64-unknown-linux-android28",
                                           apiLevel: 28)

        // --- Setup mock shell (patchelf only) ---

        let shell = MockShellExecutor()

        let swiftCorePath = swiftLibsDir.appending(path: "libswiftCore.so").fileSystemPath
        let dispatchPath = swiftLibsDir.appending(path: "libdispatch.so").fileSystemPath

        shell.patchelfOutputByPath[binaryURL.fileSystemPath] = "libMyLib.so\nlibswiftCore.so"
        shell.patchelfOutputByPath[myLibURL.fileSystemPath] = "libswiftCore.so\nlibc.so"
        shell.patchelfOutputByPath[swiftCorePath] = "libdispatch.so\nlibc.so"
        shell.patchelfOutputByPath[dispatchPath] = "libc.so"

        // --- Execute ---

        var logger = Logger(label: "test")
        logger.logLevel = .critical

        let collector = DependencyCollector(swiftSdk: swiftSdk,
                                            fileSystemService: fs,
                                            shellExecutor: shell,
                                            logger: logger)
        let pipeline = CollectAndCopyDependencies(collector: collector,
                                                   fileSystemService: fs,
                                                   logger: logger)
        try await pipeline.run(binaryURL: binaryURL,
                               buildFolderURL: buildFolder,
                               destinationURL: destination,
                               arch: .arm64)

        // --- Verify ---

        let (destFiles, _) = try fs.categorizedFolderContent(at: destination)
        let destNames = Set(destFiles.map(\.lastPathComponent))

        // Binary itself is in destination
        #expect(destNames.contains("MyTests.xctest"), "Binary should be copied to destination")

        // Transitive .so dependencies are in destination
        #expect(destNames.contains("libMyLib.so"), "Built dependency should be in destination")
        #expect(destNames.contains("libswiftCore.so"), "Swift runtime lib should be in destination")
        #expect(destNames.contains("libdispatch.so"), "Transitive dependency should be in destination")

        // System libs are NOT in destination
        #expect(destNames.contains("libc.so") == false, "System lib should NOT be collected")

        // Exact count: binary + 3 deps
        #expect(destFiles.count == 4, "Expected 4 files (binary + 3 deps), got \(destFiles.count): \(destNames)")
    }
}
