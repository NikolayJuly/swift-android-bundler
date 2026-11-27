// PackageDumping.swift

import Foundation
import ShellKit

package protocol PackageDumping: Sendable {
    func dumpPackageProducts(at packagePath: URL) async throws -> [String]
    func dumpTestTargets(at packagePath: URL) async throws -> [String]
}

// MARK: - PackageDumperImpl

package struct PackageDumperImpl: PackageDumping {
    package init() {}

    package func dumpPackageProducts(at packagePath: URL) async throws -> [String] {
        let output = try await dumpPackage(at: packagePath)
        return try PackageDumpParser.parseLibraryProductNames(from: output)
    }

    package func dumpTestTargets(at packagePath: URL) async throws -> [String] {
        let output = try await dumpPackage(at: packagePath)
        return try PackageDumpParser.parseTestTargetNames(from: output)
    }

    // MARK: - Private

    private func dumpPackage(at packagePath: URL) async throws -> String {
        try await AsyncShellCommand("swift", "package", "dump-package",
                                    "--package-path", packagePath.fileSystemPath,
                                    logger: .silent).execute()
    }
}
