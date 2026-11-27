// MockSwiftBuilder.swift

import Foundation

@testable import SwiftAndroidBuilder

final class MockSwiftBuilder: SwiftBuilding, @unchecked Sendable {

    var buildFolder = URL(filePath: "/scratch/out/Products/Debug-android-aarch64", directoryHint: .isDirectory)
    var requestedScratchPaths: [URL?] = []

    func buildProduct(_ name: String,
                      packagePath: URL,
                      configuration: BuildConfiguration,
                      triplet: String,
                      extraArgs: [String],
                      swiftVersion: String) async throws {}

    func getBuildOutputPath(packagePath: URL,
                            scratchPath: URL?,
                            configuration: BuildConfiguration,
                            triplet: String,
                            swiftVersion: String) async throws -> URL {
        requestedScratchPaths.append(scratchPath)
        return buildFolder
    }
}
