// DependencyGraphNode.swift
import Foundation

package enum SharedObjectSource: Sendable {
    /// Our .so built from source in the build folder
    case built
    /// .so from the Swift for Android SDK sysroot
    case sdk
}

package struct DependencyGraphNode: Sendable {
    package let name: String
    package let url: URL
    package let source: SharedObjectSource
    package let size: Int64
}
