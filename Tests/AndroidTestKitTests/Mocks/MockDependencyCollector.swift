// MockDependencyCollector.swift

import Foundation
import SharedStructs

@testable import DependencyCollector

struct MockDependencyCollector: DependencyCollecting {

    /// Binary file name → the .so files it loads.
    var dependenciesByBinary: [String: [URL]] = [:]

    func collect(for binaryPath: String,
                 fromBuildFolder: URL,
                 arch: AndroidArch) async throws -> [SharedObjectFile] {
        let name = URL(filePath: binaryPath).lastPathComponent
        let urls = dependenciesByBinary[name] ?? []
        return urls.map { SharedObjectFile(url: $0, size: 1) }
    }
}
