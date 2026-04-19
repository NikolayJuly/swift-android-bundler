// PostProcessing.swift

import Foundation
import ShellKit

package protocol PostProcessing: Sendable {
    func stripBinary(at url: URL, mode: StripMode, stripToolPath: String) async throws
}

// MARK: - PostProcessorImpl

package struct PostProcessorImpl: PostProcessing {
    package init() {}

    package func stripBinary(at url: URL, mode: StripMode, stripToolPath: String) async throws {
        var args = [stripToolPath]
        if mode == .debug {
            args.append("--strip-debug")
        }
        args.append(url.fileSystemPath)
        try await AsyncShellCommand(args, logger: .silent).execute()
    }
}
