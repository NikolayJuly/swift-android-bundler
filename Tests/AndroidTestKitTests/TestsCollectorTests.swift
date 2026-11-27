// TestsCollectorTests.swift

import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import LoggingExtension
import SharedStructs
import Testing

@testable import AndroidTestKit
@testable import DependencyCollector

@Suite("TestsCollector")
struct TestsCollectorTests {

    /// Scenario: no test targets given. The package's test targets come from dump-package, and each target's
    /// runner lands in the destination with the .so it loads; the scratch path reaches `--show-bin-path`.
    @Test
    func collectsEveryTestTargetOfThePackage() async throws {
        let context = try Context(runners: ["ATests", "BTests"])
        context.packageDumper.testTargets = ["ATests", "BTests"]

        try await context.collect(testTargets: [])

        let names = try context.destinationFileNames()
        #expect(names == ["ATests-test-runner", "ATests.so", "BTests-test-runner", "BTests.so", "libswiftCore.so"])
        #expect(context.builder.requestedScratchPaths == [Context.scratchPath])
    }

    /// Explicit test targets: only those are collected, and dump-package is not asked.
    @Test
    func collectsOnlyTheGivenTestTargets() async throws {
        let context = try Context(runners: ["ATests", "BTests"])

        try await context.collect(testTargets: ["BTests"])

        let names = try context.destinationFileNames()
        #expect(names == ["BTests-test-runner", "BTests.so", "libswiftCore.so"])
        #expect(context.packageDumper.dumpTestTargetsCallCount == 0)
    }

    /// A test target without a runner in the build folder fails the collection instead of being skipped.
    @Test
    func throwsWhenRunnerIsMissing() async throws {
        let context = try Context(runners: ["ATests"])

        await #expect(throws: SimpleError.self) {
            try await context.collect(testTargets: ["ATests", "MissingTests"])
        }
    }

    /// A package without test targets fails the collection.
    @Test
    func throwsWhenPackageHasNoTestTargets() async throws {
        let context = try Context(runners: [])

        await #expect(throws: SimpleError.self) {
            try await context.collect(testTargets: [])
        }
    }

    // MARK: - Private

    private final class Context {

        static let scratchPath = URL(filePath: "/repo/.build-android", directoryHint: .isDirectory)

        let fileSystem = InMemoryFileSystemService(rootUrl: URL(filePath: "/"),
                                                   appRootContainer: URL(filePath: "/app"))
        let packageDumper = MockPackageDumper()
        let builder = MockSwiftBuilder()
        let destination = URL(filePath: "/output/tests", directoryHint: .isDirectory)

        init(runners: [String]) throws {
            let buildFolder = builder.buildFolder
            try fileSystem.createAllSubfolders(upTo: buildFolder, in: URL(filePath: "/"))
            try fileSystem.createAllSubfolders(upTo: destination.deletingLastPathComponent(), in: URL(filePath: "/"))
            let swiftCore = buildFolder.appending(path: "libswiftCore.so", directoryHint: .notDirectory)
            try fileSystem.write(data: Data("elf".utf8), to: swiftCore)
            for target in runners {
                let runner = buildFolder.appending(path: target + "-test-runner", directoryHint: .notDirectory)
                let library = buildFolder.appending(path: target + ".so", directoryHint: .notDirectory)
                try fileSystem.write(data: Data("elf".utf8), to: runner)
                try fileSystem.write(data: Data("elf".utf8), to: library)
                dependencyCollector.dependenciesByBinary[runner.lastPathComponent] = [library, swiftCore]
            }
        }

        func collect(testTargets: [String]) async throws {
            let copier = CollectAndCopyDependencies(collector: dependencyCollector,
                                                    fileSystemService: fileSystem,
                                                    logger: .silent)
            let collector = TestsCollector(packageDumper: packageDumper,
                                           builder: builder,
                                           copier: copier,
                                           fileSystemService: fileSystem,
                                           logger: .silent)
            try await collector.collect(packagePath: URL(filePath: "/repo/Package", directoryHint: .isDirectory),
                                        scratchPath: Self.scratchPath,
                                        testTargets: testTargets,
                                        triplet: "aarch64-unknown-linux-android29",
                                        swiftVersion: "6.4.3",
                                        arch: .arm64,
                                        destination: destination)
        }

        func destinationFileNames() throws -> [String] {
            let (files, _) = try fileSystem.categorizedFolderContent(at: destination)
            return files
                .map(\.lastPathComponent)
                .sorted()
        }

        private var dependencyCollector = MockDependencyCollector()
    }
}
