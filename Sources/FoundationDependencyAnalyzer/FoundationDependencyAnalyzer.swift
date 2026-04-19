// FoundationDependencyAnalyzer.swift
import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import LoggingExtension
import SharedStructs
import ShellKit
import WorkPoolDraining

package struct FoundationUsageReport: Sendable {
    package let oFilePath: String
    package let targetName: String
    package let sourceFile: String
    package let symbols: [String]
}

/// Describes what to search for in `.o` files.
package struct ExcludedLibrary: Sendable {
    package let soFileNames: [String]
    /// Patterns that indicate a symbol belongs to this library (any match → included).
    /// Covers both `Foundation.SomeType` and `(extension in Foundation):` demangled forms.
    package let includePatterns: [String]
    /// Patterns that exclude a match (any match → excluded). E.g. FoundationEssentials symbols.
    package let excludePatterns: [String]
    package let title: String
    package let grepInclude: String
    package let grepExclude: String?

    package static let fullFoundation = ExcludedLibrary(soFileNames: ["libFoundation.so", "lib_FoundationICU.so", "libFoundationInternationalization.so"],
                                                        includePatterns: ["Foundation.", "(extension in Foundation):"],
                                                        excludePatterns: ["FoundationEssentials.", "(extension in FoundationEssentials):"],
                                                        title: "Foundation (full)",
                                                        grepInclude: "Foundation",
                                                        grepExclude: "FoundationEssentials")

    package static let foundationNetworking = ExcludedLibrary(soFileNames: ["libFoundationNetworking.so"],
                                                              includePatterns: ["FoundationNetworking.", "(extension in FoundationNetworking):"],
                                                              excludePatterns: [],
                                                              title: "FoundationNetworking",
                                                              grepInclude: "FoundationNetworking",
                                                              grepExclude: nil)
}

package enum FoundationDependencyAnalyzer {
    /// Checks if any of the excluded library's .so files are among the dependency names.
    package static func hasLibrary(_ library: ExcludedLibrary, in dependencyNames: Set<String>) -> Bool {
        library.soFileNames.contains { dependencyNames.contains($0) }
    }

    // MARK: - Pattern-based .o analysis (demangle + grep)

    /// Scans ALL `.o` files in the build folder for symbols matching the excluded library.
    /// Uses parallel processing limited by CPU core count.
    package static func analyzeUsage(of library: ExcludedLibrary,
                                     buildFolder: URL,
                                     ndk: AndroidNDK,
                                     fileSystemService: FileSystemService,
                                     logger: Logger) async throws -> [FoundationUsageReport] {
        let allOFiles = try fileSystemService.findAllFiles(in: buildFolder,
                                                           recursively: true,
                                                           validate: { $0.pathExtension == "o" })

        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        logger.info("[pattern] Scanning \(allOFiles.count) .o files for \(library.title) symbols (\(coreCount) parallel)...")

        let drainer = StaticAsyncWorkPoolDrainer(stack: allOFiles,
                                                 maxConcurrentOperationCount: coreCount) { oFile in
            let symbols = await findSymbolsByPattern(in: oFile, matching: library, ndk: ndk)

            guard symbols.isEmpty == false else {
                return nil as FoundationUsageReport?
            }

            let targetName = extractTargetName(from: oFile)
            return FoundationUsageReport(oFilePath: oFile.fileSystemPath,
                                         targetName: targetName,
                                         sourceFile: oFile.lastPathComponent,
                                         symbols: symbols)
        }

        var reports: [FoundationUsageReport] = []
        for try await report in drainer {
            if let report {
                reports.append(report)
            }
        }

        return reports
    }

    package static func formatReport(_ reports: [FoundationUsageReport],
                                     library: ExcludedLibrary,
                                     ndk: AndroidNDK,
                                     buildFolder: URL) -> String {
        let llvmNm = ndk.llvmNmUrl.fileSystemPath

        var output = "\n"
        output += "========================================\n"
        output += " \(library.title) dependency analysis (pattern-based)\n"
        output += "========================================\n"
        output += "\n"
        output += "To reproduce from terminal, run:\n"

        var grepChain = "grep -E '\(library.grepInclude)'"
        if let grepExclude = library.grepExclude {
            grepChain += " | grep -v -E '\(grepExclude)'"
        }
        output += "  for f in $(find \(buildFolder.fileSystemPath) -name '*.o'); do result=$(\(llvmNm) -u \"$f\" 2>/dev/null | swift demangle | \(grepChain)); if [ -n \"$result\" ]; then echo \"=== $f ===\"; echo \"$result\"; echo; fi; done\n"

        output += "\n----------------------------------------\n"

        for report in reports {
            output += "\n=== \(report.targetName) / \(report.sourceFile) ===\n"
            for symbol in report.symbols {
                output += "  \(symbol)\n"
            }
        }

        output += "\n========================================\n"
        output += " \(reports.count) file(s) with \(library.title) usage\n"
        output += "========================================\n"
        return output
    }

    // MARK: - Mangled symbol .o analysis (exact match)

    /// Scans ALL `.o` files for exact mangled symbols known from .so-level analysis.
    /// More reliable than pattern-based: searches by exact mangled name, no demangling needed per file.
    package static func analyzeUsageByMangledSymbols(_ mangledSymbols: Set<String>,
                                                     buildFolder: URL,
                                                     ndk: AndroidNDK,
                                                     fileSystemService: FileSystemService,
                                                     logger: Logger) async throws -> [FoundationUsageReport] {
        guard mangledSymbols.isEmpty == false else { return [] }

        let allOFiles = try fileSystemService.findAllFiles(in: buildFolder,
                                                           recursively: true,
                                                           validate: { $0.pathExtension == "o" })

        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        logger.info("[mangled] Scanning \(allOFiles.count) .o files for \(mangledSymbols.count) exact symbols (\(coreCount) parallel)...")

        let drainer = StaticAsyncWorkPoolDrainer(stack: allOFiles,
                                                 maxConcurrentOperationCount: coreCount) { oFile in
            let found = await findMangledSymbols(in: oFile, matching: mangledSymbols, ndk: ndk)

            guard found.isEmpty == false else {
                return nil as FoundationUsageReport?
            }

            let targetName = extractTargetName(from: oFile)
            return FoundationUsageReport(oFilePath: oFile.fileSystemPath,
                                         targetName: targetName,
                                         sourceFile: oFile.lastPathComponent,
                                         symbols: found)
        }

        var reports: [FoundationUsageReport] = []
        for try await report in drainer {
            if let report {
                reports.append(report)
            }
        }

        return reports
    }

    /// Batch-demangles Swift symbols via `swift demangle`.
    /// Returns a mapping from mangled name to demangled name.
    package static func demangleSymbols(_ mangled: some Collection<String>) async -> [String: String] {
        guard mangled.isEmpty == false else { return [:] }

        var command = ["swift", "demangle"]
        command += mangled.map { "'\($0)'" }
        let output: String
        do {
            output = try await AsyncShellCommand(command, logger: .silent).execute()
        } catch {
            return [:]
        }

        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            guard let range = lineStr.range(of: " ---> ") else { continue }
            let key = String(lineStr[lineStr.startIndex..<range.lowerBound])
            let value = String(lineStr[range.upperBound...])
            result[key] = value
        }
        return result
    }

    package static func formatMangledReport(_ reports: [FoundationUsageReport],
                                            title: String,
                                            mangledToDemangled: [String: String]) -> String {
        var output = "\n"
        output += "========================================\n"
        output += " \(title) — source file analysis (mangled match)\n"
        output += "========================================\n"

        for report in reports {
            output += "\n=== \(report.targetName) / \(report.sourceFile) ===\n"
            for symbol in report.symbols {
                let demangled = mangledToDemangled[symbol]
                if let demangled {
                    output += "  \(demangled)\n"
                    output += "    mangled: \(symbol)\n"
                } else {
                    output += "  \(symbol) (demangling failed)\n"
                }
            }
        }

        output += "\n========================================\n"
        output += " \(reports.count) file(s) with \(title) usage\n"
        output += "========================================\n"
        return output
    }
}

// MARK: - Private

private extension FoundationDependencyAnalyzer {
    /// Pattern-based: `llvm-nm -u | swift demangle`, then grep for include/exclude patterns.
    static func findSymbolsByPattern(in oFile: URL, matching library: ExcludedLibrary, ndk: AndroidNDK) async -> [String] {
        let command = AsyncShellCommand(ndk.llvmNmUrl.fileSystemPath, "-u", oFile.fileSystemPath,
                                        "|", "swift", "demangle",
                                        logger: .silent)
        let demangledOutput: String
        do {
            demangledOutput = try await command.execute()
        } catch {
            return []
        }

        return demangledOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                let matchesInclude = library.includePatterns.contains { line.contains($0) }
                guard matchesInclude else { return false }
                let matchesExclude = library.excludePatterns.contains { line.contains($0) }
                return matchesExclude == false
            }
    }

    /// Mangled match: `llvm-nm -u`, then intersect with known mangled symbol set.
    static func findMangledSymbols(in oFile: URL, matching mangledSymbols: Set<String>, ndk: AndroidNDK) async -> [String] {
        let command = AsyncShellCommand(ndk.llvmNmUrl.fileSystemPath, "-u", oFile.fileSystemPath,
                                        logger: .silent)
        let output: String
        do {
            output = try await command.execute()
        } catch {
            return []
        }

        var oFileSymbols = Set<String>()
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            if let lastSpace = trimmed.lastIndex(of: " ") {
                oFileSymbols.insert(String(trimmed[trimmed.index(after: lastSpace)...]))
            }
        }

        return mangledSymbols.intersection(oFileSymbols).sorted()
    }

    static func extractTargetName(from oFile: URL) -> String {
        let parentName = oFile.deletingLastPathComponent().lastPathComponent
        if parentName.hasSuffix(".build") {
            return String(parentName.dropLast(6))
        }
        return parentName
    }
}
