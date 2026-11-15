import Foundation

enum StorageScanner {
    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isDirectoryKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
    ]

    /// Children of `root` that this category is allowed to touch.
    static func children(of root: URL, filter: StorageCategory.Filter) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return [] }

        return entries.filter { filter.includes($0.lastPathComponent) }
    }

    /// Walks each root's children once. Sizes come from `/usr/bin/du -sk`,
    /// which is dramatically faster than a Swift enumerator on caches with
    /// hundreds of thousands of files; the recursive fallback is only used if
    /// the tool is unavailable.
    static func scan(_ category: StorageCategory, top: Int = 6) -> StorageCategorySize {
        var total: Int64 = 0
        var items: [StorageItem] = []

        for root in category.roots {
            let entries = children(of: root, filter: category.filter)
            let sizes = sizes(for: entries)

            for child in entries {
                let bytes = sizes[child.standardizedFileURL] ?? 0
                total += bytes

                guard top > 0 else { continue }
                let values = try? child.resourceValues(forKeys: sizeKeys)
                guard values?.isRegularFile == true || values?.isDirectory == true else { continue }
                items.append(StorageItem(
                    url: child,
                    name: child.lastPathComponent,
                    bytes: bytes,
                    modified: values?.contentModificationDate
                ))
            }
        }

        if top > 0 {
            items = Array(items.sorted { $0.bytes > $1.bytes }.prefix(top))
        }
        return StorageCategorySize(id: category.id, bytes: total, items: items)
    }

    static func size(of category: StorageCategory) -> Int64 {
        scan(category, top: 0).bytes
    }

    static func items(for category: StorageCategory, limit: Int = 6) -> [StorageItem] {
        scan(category, top: limit).items
    }

    private static func sizes(for urls: [URL]) -> [URL: Int64] {
        guard !urls.isEmpty else { return [:] }

        let measured = duSizes(for: urls)
        guard measured.isEmpty else { return measured }

        var fallback: [URL: Int64] = [:]
        for url in urls {
            fallback[url.standardizedFileURL] = recursiveSize(of: url)
        }
        return fallback
    }

    /// One `du -sk` per batch. Output is `<kibibytes>	<path>`; hard links are
    /// counted once per invocation, and symlinks are not followed.
    private static func duSizes(for urls: [URL]) -> [URL: Int64] {
        var result: [URL: Int64] = [:]
        let batchSize = 150

        var index = 0
        while index < urls.count {
            let batch = Array(urls[index..<min(index + batchSize, urls.count)])
            index += batchSize

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            process.arguments = ["-sk"] + batch.map(\.path)

            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continue
            }
            process.waitUntilExit()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n") {
                guard let separator = line.firstIndex(where: { $0 == "\t" || $0 == " " }) else { continue }
                let sizeText = line[..<separator].trimmingCharacters(in: .whitespaces)
                guard let kibibytes = Int64(sizeText) else { continue }
                let path = String(line[line.index(after: separator)...])
                result[URL(fileURLWithPath: path).standardizedFileURL] = kibibytes * 1_024
            }
        }

        return result
    }

    /// Allocated size of a file or directory. Directories go through `du`;
    /// symlinks are never followed.
    static func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: sizeKeys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard values.isDirectory == true else { return 0 }

        if let measured = duSizes(for: [url])[url.standardizedFileURL] {
            return measured
        }
        return recursiveSize(of: url)
    }

    private static func recursiveSize(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let itemValues = try? item.resourceValues(forKeys: sizeKeys) else { continue }
            if itemValues.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard itemValues.isRegularFile == true else { continue }
            total += Int64(itemValues.totalFileAllocatedSize ?? itemValues.fileAllocatedSize ?? itemValues.fileSize ?? 0)
        }
        return total
    }

    /// Regular files over 1 GB outside `Library`, hidden folders and packages.
    static func largeFiles(
        root: URL = StorageCatalog.home,
        minimum: Int64 = 1_000_000_000,
        limit: Int = 50
    ) -> [StorageItem] {
        let home = root.standardizedFileURL
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: home,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var items: [StorageItem] = []
        for case let url as URL in enumerator {
            if url.deletingLastPathComponent().path == home.path {
                let name = url.lastPathComponent
                if name == "Library" || name == ".Trash" {
                    enumerator.skipDescendants()
                    continue
                }
            }

            guard let values = try? url.resourceValues(forKeys: sizeKeys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }

            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            guard bytes >= minimum else { continue }
            items.append(StorageItem(
                url: url,
                name: url.lastPathComponent,
                bytes: bytes,
                modified: values.contentModificationDate
            ))
        }

        return Array(items.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }

    /// Files in Downloads untouched for `days` days.
    static func oldDownloads(
        root: URL = StorageCatalog.home.appendingPathComponent("Downloads"),
        days: Int = 90,
        limit: Int = 50,
        now: Date = Date()
    ) -> [StorageItem] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var items: [StorageItem] = []

        for url in entries {
            guard let values = try? url.resourceValues(forKeys: sizeKeys) else { continue }
            if values.isSymbolicLink == true || values.isRegularFile != true { continue }
            guard let modified = values.contentModificationDate, modified < cutoff else { continue }
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            items.append(StorageItem(url: url, name: url.lastPathComponent, bytes: bytes, modified: modified))
        }

        return Array(items.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}

enum StorageCleaner {
    /// Deletes the selected children of each root, never the root itself and
    /// never a `/Library` or system path. Symlinks are removed, not followed.
    static func clean(
        _ category: StorageCategory,
        home: URL = StorageCatalog.home
    ) -> StorageCleanResult {
        let fileManager = FileManager.default
        var result = StorageCleanResult.empty
        let homePath = home.standardizedFileURL.path + "/"

        for root in category.roots {
            guard root.standardizedFileURL.path.hasPrefix(homePath) else {
                result.failures.append("\(root.lastPathComponent): outside home")
                continue
            }

            for child in StorageScanner.children(of: root, filter: category.filter) {
                guard isContained(child, in: root) else {
                    result.failures.append("\(child.lastPathComponent): outside \(root.lastPathComponent)")
                    continue
                }

                let bytes = StorageScanner.size(of: child)
                do {
                    try fileManager.removeItem(at: child)
                    result.removedBytes += bytes
                    result.removedItems += 1
                } catch {
                    result.failures.append("\(child.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        return result
    }

    static func isContained(_ child: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        return childPath.hasPrefix(rootPath + "/")
    }
}
