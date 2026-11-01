import Foundation
import CorniceKit

// MARK: - Paths

public enum WidgetPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Cornice", isDirectory: true)
    }

    public static var widgetsDirectory: URL {
        supportDirectory.appendingPathComponent("Widgets", isDirectory: true)
    }

    public static var preferencesURL: URL {
        supportDirectory.appendingPathComponent("widgets.json")
    }
}

// MARK: - On-disk manifest

/// The JSON a widget author writes. Deliberately friendlier than the runtime struct:
/// version as a string, grid as columns/rows, capabilities as strings.
public struct DiskWidgetManifest: Decodable, Sendable {
    struct PlacementDTO: Decodable, Sendable {
        let columns: Int
        let rows: Int
        let priority: Int?
    }

    struct RefreshDTO: Decodable, Sendable {
        let interval: Double?
        let manual: Bool?
    }

    let id: String
    let name: String
    let version: String
    let apiVersion: Int
    let capabilities: [String]?
    struct CredentialDTO: Decodable, Sendable {
        struct KeychainRefDTO: Decodable, Sendable {
            let service: String
            let account: String
        }

        let host: String
        let header: String?
        let prefix: String?
        let keychain: KeychainRefDTO
    }

    struct SettingDTO: Decodable, Sendable {
        struct OptionDTO: Decodable, Sendable {
            let value: String
            let title: String
        }

        let id: String
        let title: String
        let description: String?
        let type: String
        let `default`: SettingValue
        let min: Double?
        let max: Double?
        let step: Double?
        let placeholder: String?
        let options: [OptionDTO]?
    }

    let networkHosts: [String]?
    let keychainServices: [String]?
    let credentials: [CredentialDTO]?
    let settings: [SettingDTO]?
    let placement: PlacementDTO?
    let refresh: RefreshDTO?
    let entry: String?
    let defaultEnabled: Bool?
}

public struct DiskWidget: Sendable {
    public let manifest: WidgetManifest
    public let directory: URL
    public let entry: URL
    /// First-party bundles shipped with the app can opt into being on by default.
    public let defaultEnabled: Bool
}

public enum DiskWidgetError: LocalizedError, Equatable {
    case missingManifest
    case unreadableManifest(String)
    case invalidVersion(String)
    case unknownCapability(String)
    case missingEntry(String)
    case entryEscapesBundle

    public var errorDescription: String? {
        switch self {
        case .missingManifest: return "manifest.json is missing"
        case .unreadableManifest(let detail): return "manifest.json is invalid: \(detail)"
        case .invalidVersion(let value): return "version '\(value)' is not semver"
        case .unknownCapability(let value): return "unknown capability '\(value)'"
        case .missingEntry(let path): return "entry '\(path)' does not exist"
        case .entryEscapesBundle: return "entry must stay inside the bundle"
        }
    }
}

// MARK: - Discovery

/// Component-wise containment: string prefix checks break on trailing slashes and on
/// the `/var` vs `/private/var` duality of macOS temporary directories.
enum PathContainment {
    static func contains(_ parent: URL, _ child: URL) -> Bool {
        let parentParts = normalized(parent)
        let childParts = normalized(child)
        guard childParts.count > parentParts.count else { return false }
        return Array(childParts.prefix(parentParts.count)) == parentParts
    }

    private static func normalized(_ url: URL) -> [String] {
        var parts = url.standardizedFileURL.pathComponents
        if parts.count > 1 && parts[1] == "private" {
            parts.remove(at: 1)
        }
        return parts
    }
}

public enum WidgetBundleStore {
    public static let bundleExtension = "cornicewidget"

    public struct Discovery: Sendable {
        public var widgets: [DiskWidget]
        public var errors: [String]
    }

    public static func ensureDirectoryExists(_ directory: URL = WidgetPaths.widgetsDirectory) {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? readme.write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    public static func discover(in directory: URL = WidgetPaths.widgetsDirectory) -> Discovery {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var widgets: [DiskWidget] = []
        var errors: [String] = []

        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard url.pathExtension == bundleExtension else { continue }

            do {
                widgets.append(try load(bundleAt: url))
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return Discovery(widgets: widgets, errors: errors)
    }

    public static func load(bundleAt directory: URL) throws -> DiskWidget {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = FileManager.default.contents(atPath: manifestURL.path) else {
            throw DiskWidgetError.missingManifest
        }

        let dto: DiskWidgetManifest
        do {
            dto = try JSONDecoder().decode(DiskWidgetManifest.self, from: data)
        } catch {
            throw DiskWidgetError.unreadableManifest(error.localizedDescription)
        }

        guard let version = parseVersion(dto.version) else {
            throw DiskWidgetError.invalidVersion(dto.version)
        }

        let capabilities = try (dto.capabilities ?? []).map { raw -> Capability in
            guard let capability = Capability(rawValue: raw) else {
                throw DiskWidgetError.unknownCapability(raw)
            }
            return capability
        }

        let placement = dto.placement.map {
            Placement(
                size: GridSize(columns: max(1, $0.columns), rows: max(1, $0.rows)),
                priority: $0.priority ?? 0
            )
        } ?? Placement(size: GridSize(columns: 6, rows: 3))

        let refresh: RefreshPolicy
        if let interval = dto.refresh?.interval {
            refresh = .interval(max(1, interval))
        } else {
            refresh = .manual
        }

        let credentials = (dto.credentials ?? []).map { credential in
            CredentialRule(
                host: credential.host,
                header: credential.header ?? "Authorization",
                prefix: credential.prefix ?? "Bearer ",
                service: credential.keychain.service,
                account: credential.keychain.account
            )
        }

        let settings = try (dto.settings ?? []).map { setting in
            WidgetSetting(
                id: setting.id,
                title: setting.title,
                description: setting.description,
                kind: try kind(for: setting),
                defaultValue: setting.default
            )
        }

        let manifest = WidgetManifest(
            id: dto.id,
            name: dto.name,
            version: version,
            apiVersion: dto.apiVersion,
            capabilities: Set(capabilities),
            networkHosts: dto.networkHosts ?? [],
            keychainServices: dto.keychainServices ?? [],
            credentials: credentials,
            settings: settings,
            placement: placement,
            refresh: refresh
        )

        let problems = manifest.problems
        guard problems.isEmpty else {
            throw DiskWidgetError.unreadableManifest(problems.joined(separator: ", "))
        }

        let entryName = dto.entry ?? "index.html"
        let entry = directory.appendingPathComponent(entryName).standardizedFileURL
        let root = directory.standardizedFileURL

        guard PathContainment.contains(root, entry) else {
            throw DiskWidgetError.entryEscapesBundle
        }
        guard FileManager.default.fileExists(atPath: entry.path) else {
            throw DiskWidgetError.missingEntry(entryName)
        }

        return DiskWidget(
            manifest: manifest,
            directory: root,
            entry: entry,
            defaultEnabled: dto.defaultEnabled ?? false
        )
    }

    private static func kind(for setting: DiskWidgetManifest.SettingDTO) throws -> WidgetSetting.Kind {
        switch setting.type {
        case "toggle":
            return .toggle
        case "number":
            guard let lower = setting.min, let upper = setting.max, upper > lower else {
                throw DiskWidgetError.unreadableManifest("number setting '\(setting.id)' needs min and max")
            }
            return .number(min: lower, max: upper, step: setting.step ?? 1)
        case "text":
            return .text(placeholder: setting.placeholder)
        case "select":
            let options = (setting.options ?? []).map {
                WidgetSetting.Option(value: $0.value, title: $0.title)
            }
            guard !options.isEmpty else {
                throw DiskWidgetError.unreadableManifest("select setting '\(setting.id)' needs options")
            }
            return .select(options: options)
        default:
            throw DiskWidgetError.unreadableManifest("unknown setting type '\(setting.type)'")
        }
    }

    private static func parseVersion(_ raw: String) -> SemanticVersion? {
        let parts = raw.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2])
        else { return nil }
        return SemanticVersion(major, minor, patch)
    }

    private static let readme = """
    # Cornice widgets

    Drop `*.cornicewidget` bundles here, then enable them in Options → Widgets.

    A bundle is a folder:

        MyWidget.cornicewidget/
          manifest.json
          index.html

    manifest.json:

        {
          "id": "com.example.my-widget",
          "name": "My Widget",
          "version": "1.0.0",
          "apiVersion": 1,
          "capabilities": ["network"],
          "networkHosts": ["example.com"],
          "placement": { "columns": 6, "rows": 3 },
          "refresh": { "interval": 60 },
          "entry": "index.html"
        }

    The page talks to the host through `window.cornice`:

        const response = await cornice.fetch("https://example.com/data.json");
        // { status: 200, text: "..." }

        cornice.onTick((timestamp) => { /* once per second while visible */ });

    Widgets are sandboxed: no files, no Keychain, no URLSession. Requests are limited to
    the hosts declared in the manifest.
    """
}

// MARK: - Preferences

public struct WidgetPreferences: Codable, Sendable, Equatable {
    public var enabledDiskWidgets: [WidgetID] = []
    public var disabledDiskWidgets: [WidgetID] = []
    public var disabledBuiltIns: [WidgetID] = []
    /// Explicit order, set the first time the user drags a row.
    public var order: [WidgetID] = []

    public init() {}

    /// Tolerates files written before a field existed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledDiskWidgets = try container.decodeIfPresent([String].self, forKey: .enabledDiskWidgets) ?? []
        disabledDiskWidgets = try container.decodeIfPresent([String].self, forKey: .disabledDiskWidgets) ?? []
        disabledBuiltIns = try container.decodeIfPresent([String].self, forKey: .disabledBuiltIns) ?? []
        order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
    }
}

@MainActor
public final class WidgetPreferencesStore {
    private let url: URL
    private var preferences: WidgetPreferences

    public init(url: URL = WidgetPaths.preferencesURL) {
        self.url = url
        self.preferences = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(WidgetPreferences.self, from: $0) } ?? WidgetPreferences()
    }

    public var current: WidgetPreferences { preferences }

    public func isEnabled(_ id: WidgetID, builtIn: Bool, defaultEnabled: Bool = false) -> Bool {
        if builtIn {
            return !preferences.disabledBuiltIns.contains(id)
        }
        if preferences.disabledDiskWidgets.contains(id) { return false }
        if preferences.enabledDiskWidgets.contains(id) { return true }
        return defaultEnabled
    }

    public func setOrder(_ ids: [WidgetID]) {
        preferences.order = ids
        save()
    }

    public func setEnabled(_ id: WidgetID, builtIn: Bool, _ enabled: Bool) {
        if builtIn {
            preferences.disabledBuiltIns.removeAll { $0 == id }
            if !enabled { preferences.disabledBuiltIns.append(id) }
        } else {
            preferences.enabledDiskWidgets.removeAll { $0 == id }
            preferences.disabledDiskWidgets.removeAll { $0 == id }
            if enabled {
                preferences.enabledDiskWidgets.append(id)
            } else {
                preferences.disabledDiskWidgets.append(id)
            }
        }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("[widgets] preferences save failed: \(error)\n".utf8))
        }
    }
}
