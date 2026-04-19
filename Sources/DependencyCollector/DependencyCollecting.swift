// DependencyCollecting.swift

import Foundation
import SharedStructs

package protocol DependencyCollecting: Sendable {
    func collect(for binaryPath: String,
                 fromBuildFolder: URL,
                 arch: AndroidArch) async throws -> [SharedObjectFile]
}
