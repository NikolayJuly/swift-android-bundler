// AndroidSDK.swift
import Foundation

public struct AndroidSDK: Sendable {
    public init(folder: URL) {
        self.folder = folder
    }

    public var sdkManagerUrl: URL {
        folder.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager", isDirectory: false)
    }

    public var avdManagerUrl: URL {
        folder.appendingPathComponent("cmdline-tools/latest/bin/avdmanager", isDirectory: false)
    }

    public var emulatorUrl: URL {
        folder.appendingPathComponent("emulator/emulator", isDirectory: false)
    }

    public var adbUrl: URL {
        folder.appendingPathComponent("platform-tools/adb", isDirectory: false)
    }

    // MARK: Private

    private let folder: URL
}
