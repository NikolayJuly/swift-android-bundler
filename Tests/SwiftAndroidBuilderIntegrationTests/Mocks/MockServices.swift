// MockServices.swift

import FileSystemKit
import Foundation
import Logging
import SharedStructs

@testable import DependencyGraph
@testable import SwiftAndroidBuilder

// MARK: - MockPackageDumper

final class MockPackageDumper: PackageDumping, @unchecked Sendable {
    var productsByPackage: [String: [String]] = [:]
    var dumpCallCount = 0

    func dumpPackageProducts(at packagePath: URL) async throws -> [String] {
        dumpCallCount += 1
        let key = packagePath.lastPathComponent
        guard let products = productsByPackage[key] else {
            return []
        }
        return products
    }
}

// MARK: - MockSwiftBuilder

final class MockSwiftBuilder: SwiftBuilding, @unchecked Sendable {
    /// The file system to create fake .so files in
    var fileSystem: InMemoryFileSystemService?
    /// Build folder URL to return
    var buildOutputPath: URL = URL(filePath: "/build/output")
    /// Which .so files to create in the build folder
    var soFilesToCreate: [String] = []
    struct BuildCall {
        let product: String
        let packagePath: URL
        let configuration: BuildConfiguration
        let triplet: String
    }

    var buildCalls: [BuildCall] = []
    /// Extra files to create when buildProduct is called (exact names, no lib prefix)
    var extraBuildOutputFiles: [String] = []

    func buildProduct(_ name: String, packagePath: URL, configuration: BuildConfiguration,
                      triplet: String, extraArgs: [String], swiftVersion: String) async throws {
        buildCalls.append(BuildCall(product: name,
                                     packagePath: packagePath,
                                     configuration: configuration,
                                     triplet: triplet))
        // Create fake .so file in build output
        let soName = "lib\(name).so"
        let soPath = buildOutputPath.appending(path: soName, directoryHint: .notDirectory)
        try? fileSystem?.write(data: Data("fake-\(name)".utf8), to: soPath)
        // Create extra files (e.g. executable binaries)
        for extraFile in extraBuildOutputFiles {
            let extraPath = buildOutputPath.appending(path: extraFile, directoryHint: .notDirectory)
            try? fileSystem?.write(data: Data("fake-\(extraFile)".utf8), to: extraPath)
        }
    }

    func getBuildOutputPath(packagePath: URL, configuration: BuildConfiguration,
                            triplet: String, swiftVersion: String) async throws -> URL {
        // Also create any additional .so files that should be in the build folder
        for soName in soFilesToCreate {
            let soPath = buildOutputPath.appending(path: soName, directoryHint: .notDirectory)
            if fileSystem?.fileExists(at: soPath) == false {
                try? fileSystem?.write(data: Data("fake-sdk-\(soName)".utf8), to: soPath)
            }
        }
        try? fileSystem?.createFolderIfNotExists(at: buildOutputPath)
        return buildOutputPath
    }
}

// MARK: - MockDependencyGrapher

final class MockDependencyGrapher: DependencyGraphing, @unchecked Sendable {
    var graphToReturn: DependencyGraph?
    var stripCalls: [(entries: [PatchEntry], destination: URL)] = []

    func buildGraph(soFiles: [URL], buildFolders: [URL], swiftSdk: SwiftForAndroidSDK,
                    arch: AndroidArch, ndk: AndroidNDK,
                    fileSystemService: FileSystemService,
                    logger: Logger) async throws -> DependencyGraph {
        guard let graphToReturn else {
            fatalError("MockDependencyGrapher.graphToReturn not set")
        }
        return graphToReturn
    }

    func stripPhantomEdges(_ entries: [PatchEntry], destination: URL,
                           logger: Logger) async throws -> [PatchEntry] {
        stripCalls.append((entries: entries, destination: destination))
        return entries
    }
}

// MARK: - MockPostProcessor

final class MockPostProcessor: PostProcessing, @unchecked Sendable {
    var stripCalls: [(url: URL, mode: StripMode)] = []

    func stripBinary(at url: URL, mode: StripMode, stripToolPath: String) async throws {
        stripCalls.append((url: url, mode: mode))
    }
}
