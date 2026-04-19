// PhantomEdgeStripper.swift
import Foundation
import Logging
import LoggingExtension
import ShellKit

package enum PhantomEdgeStripper {
    /// Strips NEEDED entries from copied .so files in `destinationFolder` using `patchelf --remove-needed`.
    /// Returns the list of patch entries that were actually applied.
    package static func strip(_ patchEntries: [PatchEntry],
                              destinationFolder: URL,
                              logger: Logger) async throws -> [PatchEntry] {
        guard patchEntries.isEmpty == false else {
            return []
        }

        logger.info("Stripping \(patchEntries.count) NEEDED entry(ies) from .so files in \(destinationFolder.fileSystemPath)...")

        var stripped: [PatchEntry] = []

        for entry in patchEntries {
            let filePath = destinationFolder.appending(path: entry.file, directoryHint: .notDirectory)

            try await AsyncShellCommand("patchelf", "--remove-needed", entry.removeNeeded, filePath.fileSystemPath,
                                         logger: .silent).execute()
            logger.info("Stripped \(entry.removeNeeded) from \(entry.file)")
            stripped.append(entry)
        }

        return stripped
    }
}
