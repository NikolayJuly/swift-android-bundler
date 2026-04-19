// PackageDumping.swift

import Foundation
import ShellKit

package protocol PackageDumping: Sendable {
    func dumpPackageProducts(at packagePath: URL) async throws -> [String]
}

// MARK: - PackageDumperImpl

package struct PackageDumperImpl: PackageDumping {
    package init() {}

    package func dumpPackageProducts(at packagePath: URL) async throws -> [String] {
        let output = try await AsyncShellCommand("swift", "package", "dump-package",
                                                  "--package-path", packagePath.fileSystemPath,
                                                  logger: .silent).execute()
        return try PackageDumpParser.parseLibraryProductNames(from: output)
    }
}
