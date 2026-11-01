import Foundation
import Observation

/// Everything the user can tune, persisted as JSON.
public struct CorniceSettings: Codable, Sendable, Equatable {
    public var motion: NotchMotion
    /// Seconds the pointer must rest in the hot zone before opening.
    public var hoverOpenDelay: Double
    /// Seconds the pointer may leave before collapsing.
    public var hoverCloseDelay: Double
    public var expandedWidth: Double
    public var expandedHeight: Double

    public init(
        motion: NotchMotion = NotchMotion(),
        hoverOpenDelay: Double = 0.11,
        hoverCloseDelay: Double = 0.32,
        expandedWidth: Double = 420,
        expandedHeight: Double = 170
    ) {
        self.motion = motion
        self.hoverOpenDelay = hoverOpenDelay
        self.hoverCloseDelay = hoverCloseDelay
        self.expandedWidth = expandedWidth
        self.expandedHeight = expandedHeight
    }

    public static let standard = CorniceSettings()

    public var expandedSize: CGSize {
        CGSize(width: expandedWidth, height: expandedHeight)
    }

    /// Keeps a hand-edited or corrupted file from producing an unusable app.
    public func clamped() -> CorniceSettings {
        var copy = self
        copy.motion.openResponse = motion.openResponse.clamped(to: 0.10...1.20)
        copy.motion.openDamping = motion.openDamping.clamped(to: 0.50...1.00)
        copy.motion.closeResponse = motion.closeResponse.clamped(to: 0.10...1.20)
        copy.motion.closeDamping = motion.closeDamping.clamped(to: 0.50...1.00)
        copy.motion.contentDelay = motion.contentDelay.clamped(to: 0...0.80)
        copy.motion.contentDuration = motion.contentDuration.clamped(to: 0.05...0.60)
        copy.hoverOpenDelay = hoverOpenDelay.clamped(to: 0...0.60)
        copy.hoverCloseDelay = hoverCloseDelay.clamped(to: 0...1.00)
        copy.expandedWidth = expandedWidth.clamped(to: 280...900)
        copy.expandedHeight = expandedHeight.clamped(to: 120...420)
        return copy
    }
}

/// Loads, applies and persists settings. Observing views read `settings`.
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: CorniceSettings
    /// Called after any change, so the surface can re-apply it live.
    @ObservationIgnored public var onChange: (() -> Void)?

    private let url: URL
    private var saveTask: Task<Void, Never>?

    public init(url: URL = SettingsStore.defaultURL) {
        self.url = url
        self.settings = Self.load(from: url).clamped()
    }

    public func set<T>(_ keyPath: WritableKeyPath<CorniceSettings, T>, _ value: T) {
        var next = settings
        next[keyPath: keyPath] = value
        settings = next.clamped()
        onChange?()
        scheduleSave()
    }

    public func reset() {
        settings = .standard
        onChange?()
        scheduleSave()
    }

    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Envelope(schemaVersion: 1, settings: settings))
            try data.write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("[cornice] settings save failed: \(error)\n".utf8))
        }
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Cornice/settings.json")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private static func load(from url: URL) -> CorniceSettings {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return .standard }

        return envelope.settings
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var settings: CorniceSettings
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
