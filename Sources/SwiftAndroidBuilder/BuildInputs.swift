// BuildInputs.swift

import Foundation
import SharedStructs

/// What to build and where to find it
public struct BuildRequest: Sendable {
    /// Product names to build (e.g. ["Analytics", "Payments"])
    public let products: [String]
    /// Swift package directories to search for products
    public let swiftPackages: [URL]

    public init(products: [String],
                swiftPackages: [URL]) {
        self.products = products
        self.swiftPackages = swiftPackages
    }
}

/// Target platform and toolchain
public struct BuildEnvironment: Sendable {
    public let architectures: [AndroidArch]
    public let apiLevel: Int
    public let swiftSdkPath: URL
    public let swiftVersion: String?
    public let androidSdkPath: URL
    public let configuration: BuildConfiguration

    public init(architectures: [AndroidArch],
                apiLevel: Int,
                swiftSdkPath: URL,
                swiftVersion: String?,
                androidSdkPath: URL,
                configuration: BuildConfiguration) {
        self.architectures = architectures
        self.apiLevel = apiLevel
        self.swiftSdkPath = swiftSdkPath
        self.swiftVersion = swiftVersion
        self.androidSdkPath = androidSdkPath
        self.configuration = configuration
    }
}

/// Output and post-processing options
public struct BuildOutput: Sendable {
    public let destination: URL
    public let manifestDestination: URL?
    public let excludeMode: ExcludeMode
    public let stripMode: StripMode
    public let firebaseAppId: String?
    public let symbolsDestination: URL?
    public let extraArgs: [String]

    public init(destination: URL,
                manifestDestination: URL?,
                excludeMode: ExcludeMode,
                stripMode: StripMode,
                firebaseAppId: String?,
                symbolsDestination: URL?,
                extraArgs: [String]) {
        self.destination = destination
        self.manifestDestination = manifestDestination
        self.excludeMode = excludeMode
        self.stripMode = stripMode
        self.firebaseAppId = firebaseAppId
        self.symbolsDestination = symbolsDestination
        self.extraArgs = extraArgs
    }
}
