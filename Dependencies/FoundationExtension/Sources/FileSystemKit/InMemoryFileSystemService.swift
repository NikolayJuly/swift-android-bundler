// InMemoryFileSystemService.swift
import Foundation
import FoundationExtension

/// - note: Right now this implementation is not thread safe. So write data carefully
public final class InMemoryFileSystemService: FileSystemService {

    /// - parameter rootUrl: url of root in memory folder of FS
    /// - parameter appRootContainer: Root folder which contains `Documents`,  `Library` etc
    public init(rootUrl: URL,
                appRootContainer: URL) {
        self.rootUrl = rootUrl.normalized()
        self.rootFolder = FSItem(name: rootUrl.lastPathComponent, type: .folder)
        self.appRootContainer = appRootContainer
    }

    public var tmpFolderUrl: URL { rootUrl.appendingPathComponent("tmp", isDirectory: true) }

    public var appSupportFolderUrl: URL {
        appRootContainer
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    public func folderExists(at folderUrl: URL) -> Bool {
        let item = item(at: folderUrl)
        guard let item else {
            return false
        }
        return item.type == .folder
    }

    public func fileExists(at fileUrl: URL) -> Bool {
        let item = item(at: fileUrl)
        guard let item else {
            return false
        }
        return item.type == .file
    }

    public func folderContent(at folderUrl: URL) throws -> [String] {
        let folder = try item(at: folderUrl).unwrapped()
        guard folder.type == .folder else {
            throw SimpleError("Item at \(folderUrl.path()) is not folder")
        }

        return Array(folder.content.keys)
    }

    public func write(data: Data, to url: URL) throws {
        let parentFolderUrl = url.deletingLastPathComponent()
        let parentFolder = item(at: parentFolderUrl)
        guard let parentFolder, parentFolder.type == .folder else {
            throw SimpleError("Folder at \(parentFolderUrl.absoluteString) doesn't exist")
        }

        let filename = url.lastPathComponent
        let newFile = FSItem(name: filename, data: data)
        parentFolder.$content.mutate { content in
            content[filename] = newFile
        }
    }

    public func fileContent(at url: URL) throws -> Data {
        let item = item(at: url)
        guard let item, item.type == .file else {
            throw SimpleError("File doesn't exist - \(url.absoluteString)")
        }
        return item.data
    }

    public func fileSize(at url: URL) throws -> Int64 {
        let fileContent = try fileContent(at: url)
        return Int64(fileContent.count)
    }

    public func createEmptyFolder(at folderUrl: URL) throws {
        let parentFolderUrl = folderUrl.deletingLastPathComponent()

        let parentFolder = item(at: parentFolderUrl)
        guard let parentFolder, parentFolder.type == .folder else {
            throw SimpleError("Folder doesn't exists at \(parentFolderUrl.absoluteString)")
        }

        let folderName = folderUrl.lastPathComponent

        let fsItem = FSItem(name: folderName, type: .folder)
        parentFolder.$content.mutate { content in
            content[folderName] = fsItem
        }
    }

    public func removeItem(at url: URL) throws {
        let parentUrl = url.deletingLastPathComponent()
        let parentItem = item(at: parentUrl)
        guard let parentItem, parentItem.type == .folder else {
            throw SimpleError("Parent folder doesn't exist at \(parentUrl.absoluteString)")
        }

        let name = url.lastPathComponent
        guard parentItem.content[name] != nil else {
            throw SimpleError("Item doesn't exist at \(url.absoluteString)")
        }

        parentItem.$content.mutate { content in
            content.removeValue(forKey: name)
        }
    }

    public func copyItem(at srcURL: URL, to dstURL: URL) throws {
        let srcItem = item(at: srcURL)
        guard let srcItem else {
            throw SimpleError("Source item doesn't exist at \(srcURL.absoluteString)")
        }

        let copy = srcItem.deepCopy(newName: dstURL.lastPathComponent)
        try addItem(copy, at: dstURL)
    }

    // MARK: - Private

    private let rootUrl: URL
    private let appRootContainer: URL

    private let rootFolder: FSItem

    private func addItem(_ fsItem: FSItem, at url: URL) throws {
        let parentUrl = url.deletingLastPathComponent()
        let parentItem = item(at: parentUrl)
        guard let parentItem, parentItem.type == .folder else {
            throw SimpleError("Parent folder doesn't exist at \(parentUrl.absoluteString)")
        }

        let name = url.lastPathComponent
        parentItem.$content.mutate { content in
            content[name] = fsItem
        }
    }

    private func item(at url: URL) -> FSItem? {
        let components: [String]
        do {
            components = try url.pathComponents(relativeTo: rootUrl)
        } catch {
            return nil
        }

        guard let lastItemName = components.last else {
            return rootFolder
        }

        let subFolders = components.dropLast()

        var currentItem: FSItem = rootFolder
        for component in subFolders {
            guard let folder = currentItem.content[component], folder.type == .folder else {
                return nil
            }

            currentItem = folder
        }

        return currentItem.content[lastItemName]
    }
}

private final class FSItem: @unchecked Sendable {

    enum `Type` {
        case folder
        case file
    }

    let name: String
    let type: `Type`

    @Atomic
    var content: [String: FSItem]

    @Atomic
    var data: Data

    init(name: String, data: Data) {
        self.name = name
        self.type = .file
        self.data = data
        self.content = [:]
    }

    init(name: String, content: [String: FSItem]) {
        self.name = name
        self.type = .folder
        self.data = Data()
        self.content = content
    }

    init(name: String, type: `Type`) {
        self.name = name
        self.type = type
        self.data = Data()
        self.content = [:]
    }

    func deepCopy(newName: String) -> FSItem {
        switch type {
        case .file:
            return FSItem(name: newName, data: data)
        case .folder:
            let copy = FSItem(name: newName, type: .folder)
            for (childName, childItem) in content {
                copy.content[childName] = childItem.deepCopy(newName: childName)
            }
            return copy
        }
    }
}
