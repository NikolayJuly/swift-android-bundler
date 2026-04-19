// EnvironmentValidation.swift

import Foundation
import FoundationExtension
import Logging
import LoggingExtension
import SharedStructs
import ShellKit

package enum EnvironmentValidation {
    package static func validateSwiftly(logger: Logger) async throws {
        try await checkToolExists(name: "swiftly",
                                  installHint: "see https://www.swift.org/install/",
                                  logger: logger)
    }

    package static func validatePatchelf(logger: Logger) async throws {
        try await checkToolExists(name: "patchelf",
                                  installHint: "brew install patchelf",
                                  logger: logger)
    }

    package static func validateLlvmNm(_ ndk: AndroidNDK, logger: Logger) throws {
        try checkFileExists(at: ndk.llvmNmUrl, description: "llvm-nm")
    }

    package static func validateFirebase(logger: Logger) async throws {
        try await checkToolExists(name: "firebase",
                                  installHint: "npm install -g firebase-tools",
                                  logger: logger)
    }

    package static func validateAndroidSDK(_ androidSdk: AndroidSDK, logger: Logger) throws {
        try checkFileExists(at: androidSdk.adbUrl, description: "adb")
        try checkFileExists(at: androidSdk.emulatorUrl, description: "emulator")
        try checkFileExists(at: androidSdk.sdkManagerUrl, description: "sdkmanager")
        try checkFileExists(at: androidSdk.avdManagerUrl, description: "avdmanager")
        logger.info("Android SDK validated successfully")
    }
}

// MARK: - Private

private extension EnvironmentValidation {
    static func checkToolExists(name: String,
                                installHint: String,
                                logger: Logger) async throws {
        do {
            let path = try await AsyncShellCommand("which", name, logger: .silent).execute()
            logger.info("Using \(name) - \(path.trimmingCharacters(in: .whitespacesAndNewlines))")
        } catch {
            logger.error("Failed to locate \(name): \(error)")
            throw SimpleError("\(name) is not installed or not reachable. Install it with: \(installHint). Underlying error: \(error)")
        }
    }

    static func checkFileExists(at url: URL, description: String) throws {
        guard FileManager.default.fileExists(atPath: url.fileSystemPath) else {
            throw SimpleError("\(description) not found at \(url.fileSystemPath). Make sure Android SDK is installed correctly.")
        }
    }
}
