import XCTest
@testable import CorniceHost

final class StorageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testAppCacheFilterSkipsAppleCachesAndKeepsTheRoot() throws {
        let google = try write("Google/cache.bin", bytes: 1_024)
        _ = try write("com.apple.Safari/cache.bin", bytes: 1_024)
        let other = try write("Other/file.bin", bytes: 2_048)

        let category = makeCategory(filter: .notPrefixes(["com.apple."]))
        let apple = makeCategory(id: "apple", filter: .prefixes(["com.apple."]))

        XCTAssertGreaterThan(StorageScanner.size(of: category), 0)
        XCTAssertGreaterThan(StorageScanner.size(of: apple), 0)
        XCTAssertGreaterThan(StorageScanner.size(of: google), 0)
        XCTAssertGreaterThan(StorageScanner.size(of: other), 0)

        let result = StorageCleaner.clean(category, home: root.deletingLastPathComponent())

        XCTAssertGreaterThan(result.removedBytes, 0)
        XCTAssertGreaterThan(result.removedItems, 0)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: google.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("com.apple.Safari").path
        ))
    }

    func testSymlinkIsRemovedButItsTargetSurvives() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-outside-\(UUID().uuidString).txt")
        try Data("do not delete".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let result = StorageCleaner.clean(makeCategory(filter: .all), home: root.deletingLastPathComponent())

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testContainmentRejectsPathsOutsideTheRoot() {
        let inside = root.appendingPathComponent("Google/cache.bin")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("nope")

        XCTAssertTrue(StorageCleaner.isContained(inside, in: root))
        XCTAssertFalse(StorageCleaner.isContained(outside, in: root))
    }

    func testCatalogHasUniqueIDsAndOnlyHomeRoots() {
        let categories = StorageCatalog.cleanable
        let ids = categories.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(categories.allSatisfy { category in
            category.roots.allSatisfy { $0.path.hasPrefix(StorageCatalog.home.path) }
        })
        XCTAssertTrue(categories.filter { $0.group == .recommended }.allSatisfy(\.defaultSelected))
    }


    func testLargeFilesUsesTheThresholdAndSkipsHiddenFiles() throws {
        let folder = root.appendingPathComponent("large", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let movie = folder.appendingPathComponent("movie.bin")
        try Data(repeating: 0x41, count: 2_048).write(to: movie)
        try Data(repeating: 0x41, count: 2_048).write(to: folder.appendingPathComponent(".hidden.bin"))

        let items = StorageScanner.largeFiles(root: folder, minimum: 1_024)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "movie.bin")
    }

    func testOldDownloadsUsesTheModificationDate() throws {
        let folder = root.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let old = folder.appendingPathComponent("old.bin")
        let fresh = folder.appendingPathComponent("fresh.bin")
        try Data(repeating: 0x41, count: 1_024).write(to: old)
        try Data(repeating: 0x41, count: 1_024).write(to: fresh)

        let oldDate = Date().addingTimeInterval(-100 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old.path)

        let items = StorageScanner.oldDownloads(root: folder, days: 90)

        XCTAssertEqual(items.map(\.name), ["old.bin"])
    }


    func testCleanerRefusesRootsOutsideHome() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let file = outside.appendingPathComponent("keep.bin")
        try Data("keep".utf8).write(to: file)

        let category = StorageCategory(
            id: "outside",
            group: .recommended,
            risk: .safe,
            titleEN: "Outside",
            titleES: "Outside",
            noteEN: nil,
            noteES: nil,
            roots: [outside],
            filter: .all,
            defaultSelected: true
        )

        let result = StorageCleaner.clean(category, home: root)

        XCTAssertFalse(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Helpers

    private func makeCategory(
        id: String = "test",
        filter: StorageCategory.Filter
    ) -> StorageCategory {
        StorageCategory(
            id: id,
            group: .recommended,
            risk: .safe,
            titleEN: "Test",
            titleES: "Test",
            noteEN: nil,
            noteES: nil,
            roots: [root],
            filter: filter,
            defaultSelected: true
        )
    }

    @discardableResult
    private func write(_ relativePath: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }
}
