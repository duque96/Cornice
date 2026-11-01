import Foundation
import Observation
import CorniceKit

/// Per-widget settings: defaults from the manifest, overridden by what the user saved.
@Observable
@MainActor
public final class WidgetSettingsStore {
    public private(set) var valuesByWidget: [WidgetID: [String: SettingValue]] = [:]

    private let root: URL

    public init(root: URL = WidgetPaths.widgetSettingsDirectory) {
        self.root = root
    }

    /// Called once per discovered widget so the UI can read values without mutating state.
    public func prepare(_ manifest: WidgetManifest) {
        guard valuesByWidget[manifest.id] == nil else { return }

        var values = defaults(for: manifest)
        if let saved = load(manifest.id) {
            for setting in manifest.settings {
                if let value = saved[setting.id] {
                    values[setting.id] = sanitize(value, for: setting)
                }
            }
        }
        valuesByWidget[manifest.id] = values
    }

    public func values(for manifest: WidgetManifest) -> [String: SettingValue] {
        valuesByWidget[manifest.id] ?? defaults(for: manifest)
    }

    public func set(_ value: SettingValue, for key: String, of manifest: WidgetManifest) {
        guard let setting = manifest.settings.first(where: { $0.id == key }) else { return }

        var values = values(for: manifest)
        values[key] = sanitize(value, for: setting)
        valuesByWidget[manifest.id] = values
        save(manifest.id, values: values)
    }

    // MARK: - Private

    private func defaults(for manifest: WidgetManifest) -> [String: SettingValue] {
        manifest.settings.reduce(into: [String: SettingValue]()) { result, setting in
            result[setting.id] = setting.defaultValue
        }
    }

    private func sanitize(_ value: SettingValue, for setting: WidgetSetting) -> SettingValue {
        switch setting.kind {
        case .toggle:
            return .bool(value.boolValue ?? (setting.defaultValue.boolValue ?? false))

        case .number(let lower, let upper, _):
            guard let number = value.numberValue else { return setting.defaultValue }
            return .number(min(max(number, lower), upper))

        case .text:
            return .string(value.stringValue ?? (setting.defaultValue.stringValue ?? ""))

        case .select(let options):
            let raw = value.stringValue ?? ""
            guard options.contains(where: { $0.value == raw }) else { return setting.defaultValue }
            return .string(raw)
        }
    }

    private func fileURL(_ widgetID: WidgetID) -> URL {
        root.appendingPathComponent(sanitized(widgetID), isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private func sanitized(_ widgetID: WidgetID) -> String {
        widgetID.map { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
                ? character
                : "_"
        }
        .map(String.init)
        .joined()
    }

    private func load(_ widgetID: WidgetID) -> [String: SettingValue]? {
        let url = fileURL(widgetID)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode([String: SettingValue].self, from: data)
    }

    private func save(_ widgetID: WidgetID, values: [String: SettingValue]) {
        let url = fileURL(widgetID)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(values).write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("[settings] save failed: \(error)\n".utf8))
        }
    }
}

public extension WidgetPaths {
    static var widgetSettingsDirectory: URL {
        supportDirectory.appendingPathComponent("widget-settings", isDirectory: true)
    }
}
