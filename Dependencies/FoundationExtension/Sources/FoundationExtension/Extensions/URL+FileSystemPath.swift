// URL+FileSystemPath.swift

import Foundation

public extension URL {
    /// File system path string without percent-encoding. Use this instead of `.path()` when passing paths to shell commands or file system APIs.
    var fileSystemPath: String {
        self.path(percentEncoded: false)
    }
}
