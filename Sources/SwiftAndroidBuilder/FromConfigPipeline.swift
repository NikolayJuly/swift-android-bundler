// FromConfigPipeline.swift

import DependencyGraph
import FileSystemKit
import Foundation
import FoundationDependencyAnalyzer
import FoundationExtension
import Logging
import LoggingExtension
import SharedStructs
import ShellKit

/// Orchestrates the full from-config build pipeline. One-shot: create and consume.
package struct FromConfigPipeline: ~Copyable {

    package init(request: BuildRequest,
                 environment: BuildEnvironment,
                 output: BuildOutput,
                 resolvedSwiftVersion: String,
                 ndk: AndroidNDK,
                 packageDumper: some PackageDumping,
                 builder: some SwiftBuilding,
                 graphing: some DependencyGraphing,
                 postProcessor: some PostProcessing,
                 fileSystemService: FileSystemService,
                 logger: Logger) {
        self.request = request
        self.environment = environment
        self.output = output
        self.resolvedSwiftVersion = resolvedSwiftVersion
        self.ndk = ndk
        self.packageDumper = packageDumper
        self.builder = builder
        self.graphing = graphing
        self.postProcessor = postProcessor
        self.fileSystemService = fileSystemService
        self.logger = logger
    }

    // MARK: - Package

    package consuming func run() async throws {
        let matched = try await discoverAndMatch()

        let tmpFolder = fileSystemService.tmpFolderUrl
            .appending(path: "swift-android-bundler/\(UUID().uuidString)",
                       directoryHint: .isDirectory)
        try fileSystemService.createAllSubfolders(upTo: tmpFolder,
                                                   in: fileSystemService.tmpFolderUrl)

        let sdkConfig = try SwiftSDKConfig.parse(from: environment.swiftSdkPath,
                                                   fileSystemService: fileSystemService)

        let symbolsFolder = try prepareSymbolsFolder()

        for arch in environment.architectures {
            try await processArchitecture(arch,
                                          matched: matched,
                                          sdkConfig: sdkConfig,
                                          tmpFolder: tmpFolder,
                                          symbolsFolder: symbolsFolder)
        }

        try await finalizeSymbolsArchive(symbolsFolder: symbolsFolder)
        logger.info("Done.")
    }

    // MARK: - Private

    private let symbolsTimestamp: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }()

    private let request: BuildRequest
    private let environment: BuildEnvironment
    private let output: BuildOutput
    private let resolvedSwiftVersion: String
    private let ndk: AndroidNDK
    private let packageDumper: any PackageDumping
    private let builder: any SwiftBuilding
    private let graphing: any DependencyGraphing
    private let postProcessor: any PostProcessing
    private let fileSystemService: FileSystemService
    private let logger: Logger

    private borrowing func discoverAndMatch() async throws -> [String: ProductMatcher.MatchedProduct] {
        logger.info("Phase 1: Discovery")

        var sourcePackages: [ProductMatcher.SourcePackage] = []
        for packagePath in request.swiftPackages {
            let productNames = try await packageDumper.dumpPackageProducts(at: packagePath)
            logger.info("Source \(packagePath.lastPathComponent): \(productNames.joined(separator: ", "))")
            sourcePackages.append(ProductMatcher.SourcePackage(path: packagePath,
                                                                productNames: productNames))
        }

        let matched = try ProductMatcher.match(products: request.products, sources: sourcePackages)
        logger.info("Matched \(matched.count) product(s) to source packages")
        return matched
    }

    private borrowing func processArchitecture(_ arch: AndroidArch,
                                               matched: [String: ProductMatcher.MatchedProduct],
                                               sdkConfig: SwiftSDKConfig,
                                               tmpFolder: URL,
                                               symbolsFolder: URL) async throws {
        let swiftSdk = try SwiftForAndroidSDK(sdkFolder: environment.swiftSdkPath,
                                               config: sdkConfig,
                                               arch: arch,
                                               apiLevel: environment.apiLevel)
        let triplet = swiftSdk.resolvedTriplet
        logger.info("=== Architecture: \(arch.userFriendlyName) (triplet: \(triplet)) ===")

        let (soFiles, buildFolders) = try await buildProducts(matched: matched, triplet: triplet)
        let analysis = try await analyzeGraph(soFiles: soFiles,
                                               buildFolders: buildFolders,
                                               arch: arch,
                                               swiftSdk: swiftSdk,
                                               tmpFolder: tmpFolder)

        let abiFolder = output.destination.appending(path: arch.ndkABI, directoryHint: .isDirectory)
        let copiedFiles = try await copyAndPatch(analysis, arch: arch, abiFolder: abiFolder, tmpFolder: tmpFolder)
        try await generateManifest(analysis, abiFolder: abiFolder)
        try archiveUnstrippedSymbols(copiedFiles, arch: arch, symbolsFolder: symbolsFolder)
        try await stripBinaries(copiedFiles)
        logSizes(copiedFiles, arch: arch, abiFolder: abiFolder)
    }

    private borrowing func buildProducts(matched: [String: ProductMatcher.MatchedProduct],
                                         triplet: String) async throws -> (soFiles: [URL], buildFolders: [URL]) {
        logger.info("Phase 4: Building products")

        var productsByPackage: [URL: [String]] = [:]
        for (productName, matchedProduct) in matched {
            productsByPackage[matchedProduct.packagePath, default: []].append(productName)
        }

        var allSoFiles: [URL] = []
        var allBuildFolders: [URL] = []

        for (packagePath, productNames) in productsByPackage {
            for productName in productNames {
                try await builder.buildProduct(productName,
                                               packagePath: packagePath,
                                               configuration: environment.configuration,
                                               triplet: triplet,
                                               extraArgs: output.extraArgs,
                                               swiftVersion: resolvedSwiftVersion)
            }

            let binariesFolder = try await builder.getBuildOutputPath(packagePath: packagePath,
                                                                      configuration: environment.configuration,
                                                                      triplet: triplet,
                                                                      swiftVersion: resolvedSwiftVersion)
            guard fileSystemService.folderExists(at: binariesFolder) else {
                throw SimpleError("Build output folder not found: \(binariesFolder.fileSystemPath)")
            }

            allBuildFolders.append(binariesFolder)

            let (builtFiles, _) = try fileSystemService.categorizedFolderContent(at: binariesFolder)
            for productName in productNames {
                let libName = "lib\(productName).so"
                let productSoFiles = builtFiles.filter { $0.lastPathComponent == libName }
                guard productSoFiles.isEmpty == false else {
                    throw SimpleError("Built product \(libName) not found in \(binariesFolder.fileSystemPath)")
                }
                allSoFiles.append(contentsOf: productSoFiles)
            }
        }

        guard allSoFiles.isEmpty == false else {
            throw SimpleError("No .so files found after build")
        }

        return (allSoFiles, allBuildFolders)
    }

    private borrowing func analyzeGraph(soFiles: [URL],
                                        buildFolders: [URL],
                                        arch: AndroidArch,
                                        swiftSdk: SwiftForAndroidSDK,
                                        tmpFolder: URL) async throws -> ArchAnalysis {
        logger.info("Phase 5: Building dependency graph")

        let graph = try await graphing.buildGraph(soFiles: soFiles,
                                                   buildFolders: buildFolders,
                                                   swiftSdk: swiftSdk,
                                                   arch: arch,
                                                   ndk: ndk,
                                                   fileSystemService: fileSystemService,
                                                   logger: logger)

        // Export "before" DOT graph
        let beforeDot = DependencyGraphDOTExporter.export(graph)
        let beforeDotUrl = tmpFolder.appending(path: "dependencies-\(arch.userFriendlyName)-before.dot",
                                                directoryHint: .notDirectory)
        try fileSystemService.write(data: Data(beforeDot.utf8), to: beforeDotUrl)
        logger.info("DOT graph (before): \(beforeDotUrl.fileSystemPath)")

        let rootNames = Set(soFiles.map { $0.lastPathComponent })
        let protectedLibraries: Set<String> = ["libSwiftJava.so"]

        let hasRealDependency: (String, String) -> Bool = {
            let realPairs = Set(graph.edges.filter { $0.realSymbolCount > 0 }
                                    .map { "\($0.from)->\($0.to)" })
            return { from, to in realPairs.contains("\(from)->\(to)") }
        }()

        let reachableNames: Set<String>
        let patchEntries: [PatchEntry]

        if output.excludeMode != .none {
            let cleanResult = DependencyGraphCleaner.clean(graph: graph,
                                                            roots: rootNames,
                                                            protectedLibraries: protectedLibraries,
                                                            hasRealDependency: hasRealDependency)
            reachableNames = cleanResult.reachableNodes
            patchEntries = cleanResult.patchEntries
            logger.info("After cleanup: \(reachableNames.count) .so files (was \(graph.nodes.count))")

            let excludedNames: Set<String>
            switch output.excludeMode {
            case .none:                 excludedNames = []
            case .fullFoundation:       excludedNames = Set(ExcludedLibrary.fullFoundation.soFileNames)
            case .foundationNetworking: excludedNames = Set(ExcludedLibrary.foundationNetworking.soFileNames)
            case .all:                  excludedNames = Set(ExcludedLibrary.fullFoundation.soFileNames
                                                            + ExcludedLibrary.foundationNetworking.soFileNames)
            }

            let violated = reachableNames.intersection(excludedNames)
            if violated.isEmpty == false {
                let libraries: [ExcludedLibraryReachableError.ReachableLibrary] = violated.sorted().compactMap { libName in
                    let incomingEdges = graph.edges
                        .filter { $0.to == libName && $0.realSymbolCount > 0 && excludedNames.contains($0.from) == false }
                        .map { edge in
                            ExcludedLibraryReachableError.ReachableLibrary.Edge(from: edge.from,
                                                                                symbolCount: edge.realSymbolCount,
                                                                                symbols: edge.symbols)
                        }
                    guard incomingEdges.isEmpty == false else {
                        return nil
                    }
                    return ExcludedLibraryReachableError.ReachableLibrary(name: libName,
                                                                          edges: incomingEdges)
                }
                if libraries.isEmpty == false {
                    throw ExcludedLibraryReachableError(libraries: libraries,
                                                         excludeModeName: output.excludeMode.rawValue)
                }
            }
        } else {
            reachableNames = Set(graph.nodes.keys)
            patchEntries = []
            logger.info("No cleanup — copying all \(reachableNames.count) .so files")
        }

        return ArchAnalysis(graph: graph,
                             reachableNames: reachableNames,
                             patchEntries: patchEntries,
                             hasRealDependency: hasRealDependency)
    }

    private borrowing func copyAndPatch(_ analysis: ArchAnalysis,
                                       arch: AndroidArch,
                                       abiFolder: URL,
                                       tmpFolder: URL) async throws -> [(name: String, destination: URL)] {
        try fileSystemService.createFolderIfNotExists(at: abiFolder)

        // Clean old .so files
        let (existingFiles, _) = try fileSystemService.categorizedFolderContent(at: abiFolder)
        for old in existingFiles where old.pathExtension == "so" {
            try fileSystemService.removeItem(at: old)
        }

        logger.info("Phase 6: Copying \(analysis.reachableNames.count) .so files to \(abiFolder.fileSystemPath)")

        var copiedFiles: [(name: String, destination: URL)] = []
        for name in analysis.reachableNames.sorted() {
            guard let node = analysis.graph.nodes[name] else { continue }
            let dest = abiFolder.appending(path: name, directoryHint: .notDirectory)
            try fileSystemService.copyItem(at: node.url, to: dest)
            copiedFiles.append((name, dest))
        }

        // Patch phantom edges and export "after" DOT
        let strippedEdges = try await graphing.stripPhantomEdges(analysis.patchEntries,
                                                                  destination: abiFolder,
                                                                  logger: logger)
        let afterDot = DependencyGraphDOTExporter.export(analysis.graph, strippedEdges: strippedEdges)
        let afterDotUrl = tmpFolder.appending(path: "dependencies-\(arch.userFriendlyName)-after.dot",
                                               directoryHint: .notDirectory)
        try fileSystemService.write(data: Data(afterDot.utf8), to: afterDotUrl)
        logger.info("DOT graph (after): \(afterDotUrl.fileSystemPath)")

        return copiedFiles
    }

    private borrowing func generateManifest(_ analysis: ArchAnalysis,
                                            abiFolder: URL) async throws {
        guard let manifestDir = output.manifestDestination else {
            logger.info("Manifest destination not set, skipping manifest generation")
            return
        }

        let productLabel = request.products.joined(separator: "+")
        let manifest = ManifestGenerator.generate(graph: analysis.graph,
                                                   reachableNames: analysis.reachableNames,
                                                   productName: productLabel,
                                                   hasRealDependency: analysis.hasRealDependency)
        let manifestData = try manifest.jsonData()
        let manifestUrl = manifestDir.appending(path: "swift-libs-manifest.json",
                                                directoryHint: .notDirectory)
        try fileSystemService.write(data: manifestData, to: manifestUrl)
        logger.info("Manifest: \(manifestUrl.fileSystemPath) (\(manifest.libraries.count) libraries)")
    }

    private borrowing func stripBinaries(_ copiedFiles: [(name: String, destination: URL)]) async throws {
        guard output.stripMode != .none else { return }

        logger.info("Phase 8: Stripping .so files (mode: \(output.stripMode))")
        let stripExcluded: Set<String> = ["libdispatch.so"]

        for (name, fileUrl) in copiedFiles where stripExcluded.contains(name) == false {
            try await postProcessor.stripBinary(at: fileUrl,
                                                 mode: output.stripMode,
                                                 stripToolPath: ndk.llvmStripUrl.fileSystemPath)
        }
    }

    private borrowing func logSizes(_ copiedFiles: [(name: String, destination: URL)],
                                    arch: AndroidArch,
                                    abiFolder: URL) {
        var totalSize: Int64 = 0
        for (_, fileUrl) in copiedFiles {
            totalSize += (try? fileSystemService.fileSize(at: fileUrl)) ?? 0
        }
        let totalMB = String(format: "%.2f", Double(totalSize) / 1_048_576.0)
        logger.info("\(arch.userFriendlyName): \(copiedFiles.count) files, \(totalMB) MB in \(abiFolder.fileSystemPath)")
    }

    private borrowing func prepareSymbolsFolder() throws -> URL {
        let productLabel = request.products.joined(separator: "+")
        let symbolsFolderName = "\(symbolsTimestamp)_\(productLabel)_\(environment.configuration)"
        let symbolsBaseDir: URL
        let symbolsRootDir: URL
        if let symbolsDestination = output.symbolsDestination {
            symbolsBaseDir = symbolsDestination
            symbolsRootDir = symbolsDestination
        } else {
            symbolsBaseDir = fileSystemService.appSupportFolderUrl
                .appending(path: "swift-android-bundler/symbols",
                           directoryHint: .isDirectory)
            symbolsRootDir = fileSystemService.appSupportFolderUrl
        }
        let symbolsFolder = symbolsBaseDir.appending(path: symbolsFolderName, directoryHint: .isDirectory)
        try fileSystemService.createAllSubfolders(upTo: symbolsFolder, in: symbolsRootDir)
        return symbolsFolder
    }

    private borrowing func archiveUnstrippedSymbols(_ copiedFiles: [(name: String, destination: URL)],
                                                    arch: AndroidArch,
                                                    symbolsFolder: URL) throws {
        // Snapshot unstripped binaries before any strip phase mutates them.
        // Why: symbols archive must hold the originals so they're useful for Firebase Crashlytics or post-mortem debugging.
        let archSymbolsFolder = symbolsFolder.appending(path: arch.ndkABI, directoryHint: .isDirectory)
        try fileSystemService.createFolderIfNotExists(at: archSymbolsFolder)
        for (name, source) in copiedFiles {
            let dest = archSymbolsFolder.appending(path: name, directoryHint: .notDirectory)
            try fileSystemService.copyItem(at: source, to: dest)
        }
        logger.info("Archived \(copiedFiles.count) unstripped .so file(s) for \(arch.userFriendlyName) to \(archSymbolsFolder.fileSystemPath)")
    }

    private borrowing func finalizeSymbolsArchive(symbolsFolder: URL) async throws {
        let productLabel = request.products.joined(separator: "+")
        let uploadCommands = environment.architectures.map { arch in
            let archFolder = symbolsFolder.appending(path: arch.ndkABI, directoryHint: .isDirectory)
            return """
                firebase crashlytics:symbols:upload \\
                  --app=<YOUR_FIREBASE_APP_ID> \\
                  "\(archFolder.fileSystemPath)"
                """
        }.joined(separator: "\n\n")
        let readmeContent = """
            # Debug Symbols Archive

            **Date:** \(symbolsTimestamp.replacingOccurrences(of: "_", with: " "))
            **Products:** \(productLabel)
            **Configuration:** \(environment.configuration)

            ## Upload to Firebase Crashlytics

            ```bash
            \(uploadCommands)
            ```
            """
        let readmeUrl = symbolsFolder.appending(path: "README.md", directoryHint: .notDirectory)
        try fileSystemService.write(data: Data(readmeContent.utf8), to: readmeUrl)
        logger.info("Symbols archived to \(symbolsFolder.fileSystemPath)")

        // Firebase upload (optional)
        if let firebaseAppId = output.firebaseAppId {
            logger.info("Uploading symbols to Firebase Crashlytics...")
            let printLogger = Logger(label: "PrintLogger", factory: { _ in PrintLogger() })
            for arch in environment.architectures {
                let archFolder = symbolsFolder.appending(path: arch.ndkABI, directoryHint: .isDirectory)
                try await AsyncShellCommand("firebase", "crashlytics:symbols:upload",
                                             "--app=\(firebaseAppId)",
                                             archFolder.fileSystemPath,
                                             logger: printLogger).execute()
            }
        }
    }

}

// MARK: - ArchAnalysis

private struct ArchAnalysis {
    let graph: DependencyGraph
    let reachableNames: Set<String>
    let patchEntries: [PatchEntry]
    let hasRealDependency: (String, String) -> Bool
}
