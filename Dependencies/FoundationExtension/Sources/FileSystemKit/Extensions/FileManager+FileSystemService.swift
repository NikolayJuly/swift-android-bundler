// FileManager+FileSystemService.swift
import Foundation
import FoundationExtension

#if !canImport(FoundationEssentials)
// Documentation says that ``FileManager`` is thread-safe in general, so mark as ``Sendable``
extension FileManager: @unchecked @retroactive Sendable {}
#endif

extension FileManager: FileSystemService {

    @inlinable
    public var tmpFolderUrl: URL {
        temporaryDirectory
    }

    public var appSupportFolderUrl: URL {
        #if os(iOS) || os(tvOS) || os(watchOS)
            let libraryUrls = urls(for: .libraryDirectory, in: .userDomainMask)
            return libraryUrls[0]
        #else
            let appSupportUrls = urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let appSupport = appSupportUrls[0]
            let binaryName = ProcessInfo.processInfo.processName
            return appSupport.appendingPathComponent(binaryName, isDirectory: true)
        #endif
    }

    public func folderExists(at folderUrl: URL) -> Bool {
        var isDir: ObjCBool = false
        let folderExists = fileExists(atPath: folderUrl.path, isDirectory: &isDir)
        return folderExists && isDir.boolValue
    }

    public func fileExists(at fileUrl: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileExists(atPath: fileUrl.path, isDirectory: &isDir)
        return exists && !isDir.boolValue
    }

    public func folderContent(at folderUrl: URL) throws -> [String] {
        try contentsOfDirectory(atPath: folderUrl.path)
    }

    public func write(data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    public func fileContent(at url: URL) throws -> Data {
        guard let existedFileData = contents(atPath: url.path) else {
            throw FileSystemServiceError.fileDoesntExists(url)
        }
        return existedFileData
    }

    public func fileSize(at url: URL) throws -> Int64 {
        let attributes = try attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[FileAttributeKey.size] as? Int64 else {
            throw FileSystemServiceError.fileDoesntExists(url)
        }
        return fileSize
    }

    public func createFolderIfNotExists(at folderUrl: URL) throws {
        do {
            try createDirectory(at: folderUrl, withIntermediateDirectories: false, attributes: nil)
        } catch let error where error.isFileAlreadyExists {
            let isFolder = folderExists(at: folderUrl)
            if isFolder {
                return
            }
            throw SimpleError("Trying to create folder, but system says it already exists and it is not a folder - \(folderUrl.absoluteURL)")
        } catch {
            throw SimpleError("Failed to create folder at \(folderUrl.absoluteURL): \(error)")
        }
    }

    public func createEmptyFolder(at folderUrl: URL) throws {
        try? removeItem(at: folderUrl)

        do {
            try createDirectory(at: folderUrl, withIntermediateDirectories: false, attributes: nil)
        } catch {
            throw SimpleError("Failed to create folder at \(folderUrl.absoluteURL): \(error)")
        }
    }
}

private extension Error {
    var isFileAlreadyExists: Bool {
        let nsError = self as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileWriteFileExists.rawValue
    }
}
