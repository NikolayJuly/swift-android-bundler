// PipelineIntegrationTest.swift

import FileSystemKit
import Foundation
import Logging
import SharedStructs
import Testing

@testable import DependencyGraph
@testable import SwiftAndroidBuilder

/// Integration test for the full from-config pipeline.
///
/// Scenario: "PetShop" — two Swift products from one source package.
/// - PetAnalytics and PetPayments from one source package
/// - Dependency graph has a phantom edge (libFoundation.so) that should be cleaned
/// - Verifies: discovery, build, graph cleaning, copy, manifest, symbols archive
@Suite("FromConfigPipeline integration")
struct PipelineIntegrationTest {

    @Test("Full pipeline: two products, phantom dep cleaned")
    func fullPipeline() async throws {
        // --- Setup ---

        let fs = InMemoryFileSystemService(rootUrl: URL(filePath: "/"),
                                          appRootContainer: URL(filePath: "/app"))
        let dumper = MockPackageDumper()
        let builder = MockSwiftBuilder()
        let grapher = MockDependencyGrapher()
        let postProcessor = MockPostProcessor()

        // Source package with 2 library products + 1 executable
        dumper.productsByPackage["PetShopSwift"] = ["PetAnalytics", "PetPayments"]

        // Builder setup — creates fake .so in build folder
        let buildFolder = URL(filePath: "/build/aarch64-unknown-linux-android28/release")
        builder.buildOutputPath = buildFolder
        builder.fileSystem = fs

        let graph = DependencyGraph.petShopPhantomFoundation(buildFolder: buildFolder)
        grapher.graphToReturn = graph

        try fs.setupPipelineInfrastructure(buildFolder: buildFolder)
        try fs.setupSwiftAndroidSDK()

        // Pre-create fake .so files in build folder (so categorizedFolderContent finds them)
        for node in graph.nodes.values {
            try fs.write(data: Data("elf-\(node.name)".utf8), to: node.url)
        }

        // Request
        let request = BuildRequest(products: ["PetAnalytics", "PetPayments"],
                                    swiftPackages: [URL(filePath: "/ws/PetShopSwift")])

        let environment = BuildEnvironment(architectures: [.arm64],
                                            apiLevel: 28,
                                            swiftSdkPath: URL(filePath: "/sdk/swift-android"),
                                            swiftVersion: "6.3.0",
                                            androidSdkPath: URL(filePath: "/android-sdk"),
                                            configuration: .release)

        let destination = URL(filePath: "/output/jniLibs")
        try fs.createEmptyFolder(at: URL(filePath: "/output"))
        try fs.createEmptyFolder(at: destination)

        let manifestDir = URL(filePath: "/output/manifests")
        try fs.createEmptyFolder(at: manifestDir)

        let output = BuildOutput(destination: destination,
                                  manifestDestination: manifestDir,
                                  excludeMode: .all,
                                  stripMode: .none,
                                  firebaseAppId: nil,
                                  symbolsDestination: nil,
                                  extraArgs: [])

        let ndk = AndroidNDK(ndkFolder: URL(filePath: "/android-sdk/ndk/27.0.0"))

        var logger = Logger(label: "test")
        logger.logLevel = .critical

        // --- Execute ---

        let pipeline = FromConfigPipeline(request: request,
                                         environment: environment,
                                         output: output,
                                         resolvedSwiftVersion: "6.3.0",
                                         ndk: ndk,
                                         packageDumper: dumper,
                                         builder: builder,
                                         graphing: grapher,
                                         postProcessor: postProcessor,
                                         fileSystemService: fs,
                                         logger: logger)
        try await pipeline.run()

        // --- Verify ---

        // 1. Discovery: dump was called
        #expect(dumper.dumpCallCount == 1)

        // 2. Build: both products built with correct triplet
        let builtProducts = Set(builder.buildCalls.map(\.product))
        #expect(builtProducts == ["PetAnalytics", "PetPayments"])
        #expect(builder.buildCalls.allSatisfy { $0.triplet == "aarch64-unknown-linux-android28" })

        // 4. Graph cleaning: phantom libFoundation.so should be stripped
        #expect(grapher.stripCalls.count == 1)
        let strippedEntries = grapher.stripCalls[0].entries
        #expect(strippedEntries.contains { $0.removeNeeded == "libFoundation.so" })

        // 5. Copy: correct .so files in destination/arm64-v8a/
        let abiUrl = URL(filePath: "/output/jniLibs/arm64-v8a")
        let expectedSoFiles: Set<String> = ["libPetAnalytics.so", "libPetPayments.so",
                                             "libswiftCore.so", "libdispatch.so", "libBlocksRuntime.so"]

        let (abiFiles, _) = try fs.categorizedFolderContent(at: abiUrl)
        let copiedSoNames = Set(abiFiles.filter { $0.pathExtension == "so" }.map { $0.lastPathComponent })

        #expect(copiedSoNames == expectedSoFiles, "Expected exactly \(expectedSoFiles), got \(copiedSoNames)")
        #expect(copiedSoNames.contains("libFoundation.so") == false)

        // 6. Manifest exists in manifestDestination
        let manifestUrl = manifestDir.appendingPathComponent("swift-libs-manifest.json", isDirectory: false)
        #expect(fs.fileExists(at: manifestUrl), "Manifest file should exist")

        let manifestData = try fs.fileContent(at: manifestUrl)
        let jsonObject = try JSONSerialization.jsonObject(with: manifestData)
        let json = jsonObject as? [String: Any] ?? [:]
        let libraries = json["libraries"] as? [String] ?? []

        // Load order: BlocksRuntime < dispatch < swiftCore < products
        let blocksIdx = libraries.firstIndex(of: "BlocksRuntime") ?? -1
        let dispatchIdx = libraries.firstIndex(of: "dispatch") ?? -1
        let coreIdx = libraries.firstIndex(of: "swiftCore") ?? -1

        #expect(blocksIdx < dispatchIdx, "BlocksRuntime must load before dispatch")
        #expect(dispatchIdx < coreIdx, "dispatch must load before swiftCore")
        #expect(libraries.contains("PetAnalytics"))
        #expect(libraries.contains("PetPayments"))
        #expect(libraries.contains("Foundation") == false)

        // 7. Symbols archive: .so files + README with firebase instructions (per-architecture subfolders)
        let symbolsBaseUrl = fs.appSupportFolderUrl
            .appendingPathComponent("swift-android-bundler/symbols", isDirectory: true)
        let (_, symbolSubfolders) = try fs.categorizedFolderContent(at: symbolsBaseUrl)
        #expect(symbolSubfolders.count == 1, "Should have exactly one timestamped symbols folder")

        if let symbolsFolder = symbolSubfolders.first {
            let (symbolFiles, _) = try fs.categorizedFolderContent(at: symbolsFolder)
            let symbolFileNames = symbolFiles.map { $0.lastPathComponent }

            #expect(symbolFileNames.contains("README.md"))

            // Symbols are stored in per-architecture subfolders
            let archSymbolsFolder = symbolsFolder.appendingPathComponent("arm64-v8a", isDirectory: true)
            let (archSymbolFiles, _) = try fs.categorizedFolderContent(at: archSymbolsFolder)
            let soSymbols = archSymbolFiles.filter { $0.pathExtension == "so" }.map { $0.lastPathComponent }
            #expect(soSymbols.isEmpty == false, "Symbols archive should contain .so files in arch subfolder")

            let readmeUrl = symbolsFolder.appendingPathComponent("README.md", isDirectory: false)
            let readmeData = try fs.fileContent(at: readmeUrl)
            let readmeText = String(data: readmeData, encoding: .utf8) ?? ""
            #expect(readmeText.contains("firebase crashlytics:symbols:upload"))
        }
    }

    /// Scenario: CI (Linux) — no pre-existing intermediate directories.
    /// Neither `/tmp/swift-android-bundler/` nor the symbols destination chain exist.
    /// The pipeline must create all intermediate folders automatically.
    @Test("Pipeline creates intermediate directories on fresh CI environment")
    func pipelineCreatesIntermediateDirectories() async throws {
        let fs = InMemoryFileSystemService(rootUrl: URL(filePath: "/"),
                                          appRootContainer: URL(filePath: "/app"))
        let dumper = MockPackageDumper()
        let builder = MockSwiftBuilder()
        let grapher = MockDependencyGrapher()
        let postProcessor = MockPostProcessor()

        dumper.productsByPackage["PetShopSwift"] = ["PetAnalytics"]

        let buildFolder = URL(filePath: "/build/x86_64-unknown-linux-android28/release")
        builder.buildOutputPath = buildFolder
        builder.fileSystem = fs

        let graph = DependencyGraph.petShopPhantomFoundation(buildFolder: buildFolder)
        grapher.graphToReturn = graph

        // Only create /tmp — do NOT create /tmp/swift-android-bundler/
        try fs.createEmptyFolder(at: URL(filePath: "/tmp"))

        // Build folder chain
        try fs.createFolderChain(at: buildFolder)

        try fs.setupSwiftAndroidSDK()

        for node in graph.nodes.values {
            try fs.write(data: Data("elf-\(node.name)".utf8), to: node.url)
        }

        let request = BuildRequest(products: ["PetAnalytics"],
                                    swiftPackages: [URL(filePath: "/ws/PetShopSwift")])

        let environment = BuildEnvironment(architectures: [.arm64],
                                            apiLevel: 28,
                                            swiftSdkPath: URL(filePath: "/sdk/swift-android"),
                                            swiftVersion: "6.3.0",
                                            androidSdkPath: URL(filePath: "/android-sdk"),
                                            configuration: .release)

        let destination = URL(filePath: "/output/jniLibs")
        try fs.createFolderChain(at: destination)

        // Custom symbols destination — pre-created by user on CI
        let symbolsDir = URL(filePath: "/ci/artifacts/symbols")
        try fs.createFolderChain(at: symbolsDir)

        let output = BuildOutput(destination: destination,
                                  manifestDestination: nil,
                                  excludeMode: .all,
                                  stripMode: .none,
                                  firebaseAppId: nil,
                                  symbolsDestination: symbolsDir,
                                  extraArgs: [])

        let ndk = AndroidNDK(ndkFolder: URL(filePath: "/android-sdk/ndk/27.0.0"))

        var logger = Logger(label: "test")
        logger.logLevel = .critical

        let pipeline = FromConfigPipeline(request: request,
                                         environment: environment,
                                         output: output,
                                         resolvedSwiftVersion: "6.3.0",
                                         ndk: ndk,
                                         packageDumper: dumper,
                                         builder: builder,
                                         graphing: grapher,
                                         postProcessor: postProcessor,
                                         fileSystemService: fs,
                                         logger: logger)
        try await pipeline.run()

        // Verify: /tmp/swift-android-bundler/ was created (with UUID subfolder)
        let tmpBase = URL(filePath: "/tmp/swift-android-bundler")
        #expect(fs.folderExists(at: tmpBase), "Intermediate /tmp/swift-android-bundler/ should be created")

        // Verify: symbols were archived in the custom destination
        let (_, symbolSubfolders) = try fs.categorizedFolderContent(at: symbolsDir)
        #expect(symbolSubfolders.count == 1, "Should have one timestamped symbols folder in custom destination")

        if let symbolsFolder = symbolSubfolders.first {
            let archSymbolsFolder = symbolsFolder.appendingPathComponent("arm64-v8a", isDirectory: true)
            let (archFiles, _) = try fs.categorizedFolderContent(at: archSymbolsFolder)
            let soNames = archFiles.filter { $0.pathExtension == "so" }.map { $0.lastPathComponent }
            #expect(soNames.isEmpty == false, "Symbols archive should contain .so files")
        }
    }

    /// Scenario: build with `stripMode: .all` and a custom symbols destination.
    /// The pipeline must archive the *unstripped* originals into the symbols folder
    /// before applying strip to the deliverable .so files in jniLibs.
    ///
    /// The check is by file content, not by phase order: the mock post-processor mutates each
    /// stripped file by prepending a `STRIPPED:` marker. We then assert that no file inside
    /// the symbols archive carries that marker, while files in jniLibs (except libdispatch.so,
    /// which is in the strip exclude list) do.
    @Test("Symbols archive must contain unstripped binaries when strip is enabled")
    func symbolsArchivePreservesUnstrippedBinaries() async throws {
        // --- Setup ---

        let fs = InMemoryFileSystemService(rootUrl: URL(filePath: "/"),
                                          appRootContainer: URL(filePath: "/app"))
        let dumper = MockPackageDumper()
        let builder = MockSwiftBuilder()
        let grapher = MockDependencyGrapher()
        let postProcessor = MockPostProcessor()
        postProcessor.fileSystem = fs

        dumper.productsByPackage["PetShopSwift"] = ["PetAnalytics", "PetPayments"]

        let buildFolder = URL(filePath: "/build/aarch64-unknown-linux-android28/release")
        builder.buildOutputPath = buildFolder
        builder.fileSystem = fs

        let graph = DependencyGraph.petShopPhantomFoundation(buildFolder: buildFolder)
        grapher.graphToReturn = graph

        try fs.setupPipelineInfrastructure(buildFolder: buildFolder)
        try fs.setupSwiftAndroidSDK()

        // Seed build folder so categorizedFolderContent finds the files. Note: MockSwiftBuilder.buildProduct
        // will overwrite product .so files during the run; non-product SDK .so files keep this seed.
        // We snapshot the actual pre-strip bytes from buildFolder after the run — that's the ground truth
        // because strip mutates only the abiFolder copies.
        for node in graph.nodes.values {
            try fs.write(data: Data("ELF:\(node.name):DEBUG_SECTION".utf8), to: node.url)
        }

        let request = BuildRequest(products: ["PetAnalytics", "PetPayments"],
                                    swiftPackages: [URL(filePath: "/ws/PetShopSwift")])

        let environment = BuildEnvironment(architectures: [.arm64],
                                            apiLevel: 28,
                                            swiftSdkPath: URL(filePath: "/sdk/swift-android"),
                                            swiftVersion: "6.3.0",
                                            androidSdkPath: URL(filePath: "/android-sdk"),
                                            configuration: .release)

        let destination = URL(filePath: "/output/jniLibs")
        try fs.createEmptyFolder(at: URL(filePath: "/output"))
        try fs.createEmptyFolder(at: destination)

        let symbolsDir = URL(filePath: "/output/symbols")
        try fs.createEmptyFolder(at: symbolsDir)

        let output = BuildOutput(destination: destination,
                                  manifestDestination: nil,
                                  excludeMode: .all,
                                  stripMode: .all,
                                  firebaseAppId: nil,
                                  symbolsDestination: symbolsDir,
                                  extraArgs: [])

        let ndk = AndroidNDK(ndkFolder: URL(filePath: "/android-sdk/ndk/27.0.0"))

        var logger = Logger(label: "test")
        logger.logLevel = .critical

        // --- Execute ---

        let pipeline = FromConfigPipeline(request: request,
                                         environment: environment,
                                         output: output,
                                         resolvedSwiftVersion: "6.3.0",
                                         ndk: ndk,
                                         packageDumper: dumper,
                                         builder: builder,
                                         graphing: grapher,
                                         postProcessor: postProcessor,
                                         fileSystemService: fs,
                                         logger: logger)
        try await pipeline.run()

        // --- Verify ---

        // Sanity: the strip mock was actually invoked. Without this, the rest of the asserts
        // could pass trivially if strip silently became a no-op.
        #expect(postProcessor.stripCalls.isEmpty == false, "Strip must run when stripMode is .all")

        let strippedPrefixBytes = Data(MockPostProcessor.strippedPrefix.utf8)

        // Pre-strip ground truth: buildFolder is not touched by strip, so whatever is there now
        // is exactly what symbols archive must hold.
        var originalBytesByName: [String: Data] = [:]
        for node in graph.nodes.values {
            originalBytesByName[node.name] = try fs.fileContent(at: node.url)
        }

        // 1. Symbols archive: every .so under <symbolsDir>/<timestamp>/<arch> must be byte-identical to the original.
        let (_, symbolSubfolders) = try fs.categorizedFolderContent(at: symbolsDir)
        #expect(symbolSubfolders.count == 1, "Expected exactly one timestamped symbols subfolder")
        let symbolsFolder = try #require(symbolSubfolders.first)

        let archSymbolsFolder = symbolsFolder.appendingPathComponent("arm64-v8a", isDirectory: true)
        let (archSymbolFiles, _) = try fs.categorizedFolderContent(at: archSymbolsFolder)
        let soSymbols = archSymbolFiles.filter { $0.pathExtension == "so" }
        #expect(soSymbols.isEmpty == false, "Symbols archive must contain .so files")

        for soUrl in soSymbols {
            let name = soUrl.lastPathComponent
            let bytes = try fs.fileContent(at: soUrl)
            #expect(bytes.starts(with: strippedPrefixBytes) == false,
                    "Symbols archive must not contain stripped binary: \(name)")
            if let expected = originalBytesByName[name] {
                #expect(bytes == expected,
                        "Symbols archive file \(name) must be byte-identical to the pre-strip build output")
            }
        }

        // 2. jniLibs: every .so (except libdispatch.so) must carry the strip marker — confirms strip ran on deliverables.
        let abiFolder = destination.appendingPathComponent("arm64-v8a", isDirectory: true)
        let (abiFiles, _) = try fs.categorizedFolderContent(at: abiFolder)
        let abiSoFiles = abiFiles.filter { $0.pathExtension == "so" }
        #expect(abiSoFiles.isEmpty == false, "jniLibs must contain .so files")

        let stripExcluded: Set<String> = ["libdispatch.so"]
        for soUrl in abiSoFiles {
            let name = soUrl.lastPathComponent
            let bytes = try fs.fileContent(at: soUrl)
            if stripExcluded.contains(name) {
                #expect(bytes.starts(with: strippedPrefixBytes) == false,
                        "\(name) is in the strip exclude list and must not be stripped")
            } else {
                #expect(bytes.starts(with: strippedPrefixBytes),
                        "\(name) in jniLibs must be stripped when stripMode is .all")
            }
        }
    }

    /// Scenario: product has real symbol dependencies on libFoundation.so and lib_FoundationICU.so,
    /// but excludeMode is .all. The pipeline must throw ExcludedLibraryReachableError listing
    /// the violated libraries and the symbols that connect them.
    @Test("Pipeline throws when excluded Foundation libraries are reachable via real edges")
    func excludedFoundationReachableThrows() async throws {
        // --- Setup ---

        let fs = InMemoryFileSystemService(rootUrl: URL(filePath: "/"),
                                          appRootContainer: URL(filePath: "/app"))
        let dumper = MockPackageDumper()
        let builder = MockSwiftBuilder()
        let grapher = MockDependencyGrapher()
        let postProcessor = MockPostProcessor()

        dumper.productsByPackage["Analytics"] = ["SwiftLibraryAndroid"]

        let buildFolder = URL(filePath: "/build/aarch64-unknown-linux-android28/release")
        builder.buildOutputPath = buildFolder
        builder.fileSystem = fs

        let graph = DependencyGraph.analyticsRealFoundation(buildFolder: buildFolder)
        grapher.graphToReturn = graph

        try fs.setupPipelineInfrastructure(buildFolder: buildFolder)
        try fs.setupSwiftAndroidSDK()

        for node in graph.nodes.values {
            try fs.write(data: Data("elf-\(node.name)".utf8), to: node.url)
        }

        let request = BuildRequest(products: ["SwiftLibraryAndroid"],
                                    swiftPackages: [URL(filePath: "/ws/Analytics")])

        let environment = BuildEnvironment(architectures: [.arm64],
                                            apiLevel: 28,
                                            swiftSdkPath: URL(filePath: "/sdk/swift-android"),
                                            swiftVersion: "6.3.0",
                                            androidSdkPath: URL(filePath: "/android-sdk"),
                                            configuration: .release)

        let destination = URL(filePath: "/output/jniLibs")
        try fs.createEmptyFolder(at: URL(filePath: "/output"))
        try fs.createEmptyFolder(at: destination)

        let output = BuildOutput(destination: destination,
                                  manifestDestination: nil,
                                  excludeMode: .all,
                                  stripMode: .none,
                                  firebaseAppId: nil,
                                  symbolsDestination: nil,
                                  extraArgs: [])

        let ndk = AndroidNDK(ndkFolder: URL(filePath: "/android-sdk/ndk/27.0.0"))

        var logger = Logger(label: "test")
        logger.logLevel = .critical

        // --- Execute & Verify ---

        let pipeline = FromConfigPipeline(request: request,
                                         environment: environment,
                                         output: output,
                                         resolvedSwiftVersion: "6.3.0",
                                         ndk: ndk,
                                         packageDumper: dumper,
                                         builder: builder,
                                         graphing: grapher,
                                         postProcessor: postProcessor,
                                         fileSystemService: fs,
                                         logger: logger)

        do {
            try await pipeline.run()
            Issue.record("Pipeline must throw ExcludedLibraryReachableError when excluded libraries are reachable")
        } catch let error as ExcludedLibraryReachableError {
            let description = error.errorDescription ?? ""
            #expect(description.contains("libFoundation.so"))
            #expect(description.contains("$s10Foundation4DateVMn"))

            let libraryNames = Set(error.libraries.map(\.name))
            #expect(libraryNames.contains("libFoundation.so"))

            // Libraries reachable only through other excluded libs should NOT appear
            #expect(libraryNames.contains("lib_FoundationICU.so") == false)
        } catch {
            Issue.record("Expected ExcludedLibraryReachableError, got \(type(of: error)): \(error)")
        }
    }
}
