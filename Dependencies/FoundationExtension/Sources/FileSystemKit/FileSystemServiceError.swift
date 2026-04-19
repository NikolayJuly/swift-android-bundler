// FileSystemServiceError.swift
import Foundation

public enum FileSystemServiceError: LocalizedError, CustomNSError {

    case fileDoesntExists(URL)
    case unableToCreateWriteFileStream(URL)
    case rootUrlDoNotContainDesired(rootUrl: URL, desired: URL)

    // MARK: CustomNSError

    public static let errorDomain: String = "FileSystemServiceError"

    public var errorCode: Int {
        switch self {
        case .fileDoesntExists: return 1
        case .unableToCreateWriteFileStream: return 2
        case .rootUrlDoNotContainDesired: return 3
        }
    }

    // MARK: LocalizedError

    public var description: String {
        switch self {
        case .fileDoesntExists(let fileUrl):
            return "File at \(fileUrl.path) can't be found (FileSystemServiceError.fileDoesntExists)"

        case .unableToCreateWriteFileStream(let fileUrl):
            return "Can't create writing stream at \(fileUrl.path) (FileSystemServiceError.unableToCreateWriteFileStream)"

        case .rootUrlDoNotContainDesired(let rootUrl, let desired):
            return "Root path is not part of desired one. Root: \"(\(rootUrl.path)\", deisered: \"\(desired.path)\" (FileSystemServiceError.rootUrlDoNotContainDesired)"
        }
    }
}
