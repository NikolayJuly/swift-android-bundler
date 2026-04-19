// FileSystemService.swift
import CoreFoundation
import Foundation
import FoundationExtension

public protocol FileSystemService: AnyObject, Sendable {

    var tmpFolderUrl: URL { get }

    /// Application Support folder. macOS: ~/Library/Application Support/{binary-name}/, iOS: same as libraryFolderUrl
    var appSupportFolderUrl: URL { get }

    /// Check that folder at URL exists and it is folder, not a file
    func folderExists(at folderUrl: URL) -> Bool

    /// Check that file at URL exists and it is file, not a folder
    func fileExists(at fileUrl: URL) -> Bool

    /// - returns: files and subfolder names
    func folderContent(at folderUrl: URL) throws -> [String]

    func write(data: Data, to url: URL) throws

    /// - Throws: FileSystemServiceError
    func fileContent(at url: URL) throws -> Data

    func fileSize(at url: URL) throws -> Int64

    /// If folder exists - it will be deleted and recreated.
    /// All parent folders in path must exists
    func createEmptyFolder(at folderUrl: URL) throws

    func removeItem(at URL: URL) throws

    func copyItem(at srcURL: URL, to dstURL: URL) throws
}

public extension FileSystemService {

    /// If folder exists - nothing happen. If not - will be created.
    func createFolderIfNotExists(at folderUrl: URL) throws {
        guard !folderExists(at: folderUrl) else {
            return
        }
        try createEmptyFolder(at: folderUrl)
    }

    /// Create all needed subfolders starts from `rootFolderUrl`. If any folder in chain existed, it will stay untouched
    func createAllSubfolders(upTo targetFolderUrl: URL, in rootFolderUrl: URL) throws {
        try createFolderIfNotExists(at: rootFolderUrl)

        let subPathComponents = try targetFolderUrl.pathComponents(relativeTo: rootFolderUrl)

        var currentFolderUrl = rootFolderUrl
        for pathComponent in subPathComponents {
            currentFolderUrl = currentFolderUrl.appendingPathComponent(pathComponent, isDirectory: true)
            try createFolderIfNotExists(at: currentFolderUrl)
        }
    }

    /// - returns: files and subfolder URLs, excluding .DS_Store
    func categorizedFolderContent(at folderUrl: URL) throws -> (files: [URL], folders: [URL]) {
        let contents = try folderContent(at: folderUrl)

        var files = [URL]()
        var folders = [URL]()
        folders.reserveCapacity(contents.count)
        files.reserveCapacity(contents.count)

        for content in contents {
            let itemUrl = folderUrl.appendingPathComponent(content)

            if folderExists(at: itemUrl) {
                folders.append(itemUrl)
            } else {
                guard itemUrl.lastPathComponent != ".DS_Store" else {
                    continue
                }
                files.append(itemUrl)
            }
        }
        return (files, folders)
    }

    /// Check all files, if `recursively` is true, check all subfolder etc
    @inlinable
    func findAllFiles(in folderUrl: URL, recursively: Bool) throws -> [URL] {
        try findAllFiles(in: folderUrl, recursively: recursively, validate: { _ in true })
    }

    /// - Parameter validate: block to validate file. Return true to include file in result
    func findAllFiles(in folderUrl: URL, recursively: Bool, validate: (URL) -> Bool) throws -> [URL] {
        var foldersToCheck: [URL] = [folderUrl]
        var resFiles = [URL]()

        while let folderUrl = foldersToCheck.last {
            foldersToCheck = Array(foldersToCheck.dropLast())

            let (files, folders) = try categorizedFolderContent(at: folderUrl)

            if recursively {
                foldersToCheck.append(contentsOf: folders)
            }

            for fileUrl in files {
                guard fileUrl.lastPathComponent != ".DS_Store" else {
                    continue
                }
                guard validate(fileUrl) else {
                    continue
                }
                resFiles.append(fileUrl)
            }
        }

        return resFiles
    }
}
