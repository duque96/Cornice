import Foundation
import CorniceKit

public extension Notification.Name {
    /// Posted by the storage service when a widget asks for the review window.
    static let corniceShowStorage = Notification.Name("cornice.showStorage")
}

/// Volume status plus the allow-listed cleaner. The actor keeps the heavy
/// directory walks off the main thread; the SDK only exposes status and the
/// review action.
public actor SystemStorage: StorageControlling {
    private var cachedRecommended: (date: Date, sizes: [StorageCategorySize])?
    private var cachedAdvanced: (date: Date, sizes: [StorageCategorySize])?

    public init() {}

    // MARK: - StorageControlling

    public func status() async -> StorageStatus? {
        guard let capacity = volumeCapacity() else { return nil }
        let recommended = await scanRecommended()
        let recoverable = recommended.reduce(Int64(0)) { $0 + $1.bytes }

        return StorageStatus(
            totalBytes: capacity.total,
            freeBytes: capacity.free,
            usedBytes: max(Int64(0), capacity.total - capacity.free),
            recoverableBytes: recoverable
        )
    }

    /// Capacity only, without walking the cache trees. The review window uses
    /// this to paint the bar immediately.
    func capacity() -> StorageStatus? {
        guard let capacity = volumeCapacity() else { return nil }
        return StorageStatus(
            totalBytes: capacity.total,
            freeBytes: capacity.free,
            usedBytes: max(Int64(0), capacity.total - capacity.free),
            recoverableBytes: 0
        )
    }

    public func review() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .corniceShowStorage, object: nil)
        }
    }

    // MARK: - Review window

    func scanRecommended() async -> [StorageCategorySize] {
        if let cached = cachedRecommended, Date().timeIntervalSince(cached.date) < 300 {
            return cached.sizes
        }
        let sizes = StorageCatalog.cleanable
            .filter { $0.group == .recommended }
            .map { StorageScanner.scan($0) }
        cachedRecommended = (Date(), sizes)
        return sizes
    }

    func scanAdvanced() async -> [StorageCategorySize] {
        if let cached = cachedAdvanced, Date().timeIntervalSince(cached.date) < 300 {
            return cached.sizes
        }
        let sizes = StorageCatalog.cleanable
            .filter { $0.group == .advanced }
            .map { StorageScanner.scan($0) }
        cachedAdvanced = (Date(), sizes)
        return sizes
    }

    func scanAll() async -> [StorageCategorySize] {
        await scanRecommended() + scanAdvanced()
    }

    func clean(ids: Set<String>) async -> StorageCleanResult {
        var result = StorageCleanResult.empty
        for category in StorageCatalog.cleanable where ids.contains(category.id) {
            result.merge(StorageCleaner.clean(category))
        }
        cachedRecommended = nil
        cachedAdvanced = nil
        return result
    }

    func largeFiles() async -> [StorageItem] {
        StorageScanner.largeFiles()
    }

    func oldDownloads(days: Int = 90) async -> [StorageItem] {
        StorageScanner.oldDownloads(days: days)
    }

    func trash(_ url: URL) async -> String? {
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func localSnapshotCount() async -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
    }

    // MARK: - Private

    private func volumeCapacity() -> (total: Int64, free: Int64)? {
        let root = URL(fileURLWithPath: "/")
        guard let values = try? root.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]) else { return nil }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        guard total > 0 else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage
        let plain = values.volumeAvailableCapacity.map(Int64.init)
        let free = important ?? plain ?? 0
        return (total, free)
    }
}
