// AndroidArch.swift
import FoundationExtension

public struct AndroidArch: Hashable, Sendable {
    public let name: String
    /// User-friendly CLI name: arm64, arm7, x86, x86_64
    public let userFriendlyName: String
    public let ndkABI: String
    public let ndkPlatform: String
    public let ndkLibArchName: String
    public let swiftArch: String
    public let swiftTarget: String

    /// Looks up AndroidArch by CLI name (arm64, arm7, x86, x86_64)
    public static func fromUserFriendlyName(_ name: String) -> AndroidArch? {
        allCases.first { $0.userFriendlyName == name }
    }

    /// Parses arch and API level from a triplet string (e.g. "aarch64-unknown-linux-android28")
    public static func parse(triplet: String) throws -> (arch: AndroidArch, apiLevel: Int) {
        guard let arch = allCases.first(where: { triplet.hasPrefix($0.swiftTarget) }) else {
            throw SimpleError("Cannot determine architecture from triplet '\(triplet)'")
        }
        let trailingDigits = String(triplet.reversed().prefix(while: \.isNumber).reversed())
        guard let apiLevel = Int(trailingDigits) else {
            throw SimpleError("Cannot extract API level from triplet '\(triplet)'")
        }
        return (arch, apiLevel)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ndkABI == rhs.ndkABI
    }
}

extension AndroidArch: CaseIterable {
    public static let allCases: [AndroidArch] = [
        arm64,
        arm7,
        x86,
        x86_64,
    ]

    public static let arm64 = AndroidArch(name: "aarch64",
                                          userFriendlyName: "arm64",
                                          ndkABI: "arm64-v8a",
                                          ndkPlatform: "arch-arm64",
                                          ndkLibArchName: "aarch64-linux-android",
                                          swiftArch: "aarch64",
                                          swiftTarget: "aarch64-unknown-linux-android")

    public static let arm7 = AndroidArch(name: "armv7a",
                                         userFriendlyName: "arm7",
                                         ndkABI: "armeabi-v7a",
                                         ndkPlatform: "arch-arm",
                                         ndkLibArchName: "arm-linux-androideabi",
                                         swiftArch: "armv7",
                                         swiftTarget: "armv7-unknown-linux-androideabi")

    public static let x86 = AndroidArch(name: "x86",
                                        userFriendlyName: "x86",
                                        ndkABI: "x86",
                                        ndkPlatform: "arch-x86",
                                        ndkLibArchName: "i686-linux-android",
                                        swiftArch: "i686",
                                        swiftTarget: "i686-unknown-linux-android")

    public static let x86_64 = AndroidArch(name: "x86_64",
                                           userFriendlyName: "x86_64",
                                           ndkABI: "x86_64",
                                           ndkPlatform: "arch-x86_64",
                                           ndkLibArchName: "x86_64-linux-android",
                                           swiftArch: "x86_64",
                                           swiftTarget: "x86_64-unknown-linux-android")

}

