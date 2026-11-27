// MockPackageDumper.swift

import Foundation

@testable import SwiftAndroidBuilder

final class MockPackageDumper: PackageDumping, @unchecked Sendable {

    var testTargets: [String] = []
    var dumpTestTargetsCallCount = 0

    func dumpPackageProducts(at packagePath: URL) async throws -> [String] {
        []
    }

    func dumpTestTargets(at packagePath: URL) async throws -> [String] {
        dumpTestTargetsCallCount += 1
        return testTargets
    }
}
