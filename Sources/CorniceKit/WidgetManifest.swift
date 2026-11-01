import Foundation

public typealias WidgetID = String

/// Language the host resolved for this session. Widgets localize themselves.
public enum WidgetLanguage: String, Codable, Sendable, CaseIterable {
    case en
    case es

    public var localeIdentifier: String {
        switch self {
        case .en: return "en_GB"
        case .es: return "es_ES"
        }
    }
}

// MARK: - Version

public struct SemanticVersion: Codable, Sendable, Equatable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

// MARK: - Capabilities

/// What a widget is allowed to touch. The host grants these from the manifest;
/// a widget never reaches the system directly.
public enum Capability: String, Codable, Sendable, CaseIterable {
    case network
    case keychain
    case files
    case calendar
    case media
    case notifications
    /// Connect and disconnect Tailscale. Privileged: grants command execution
    /// through the host, scoped to the `tailscale` CLI.
    case tailscale
}

// MARK: - Layout

public struct GridSize: Codable, Sendable, Hashable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

public enum Slot: String, Codable, Sendable {
    /// The expanded panel.
    case stage
}

public struct Placement: Codable, Sendable, Equatable {
    public let slot: Slot
    public let size: GridSize
    /// Higher wins when the panel cannot fit everything.
    public let priority: Int

    public init(slot: Slot = .stage, size: GridSize, priority: Int = 0) {
        self.slot = slot
        self.size = size
        self.priority = priority
    }
}

// MARK: - Refresh

public enum RefreshPolicy: Sendable, Equatable {
    case manual
    case interval(TimeInterval)
}

// MARK: - Credentials

/// A secret the host injects into requests for one host. The widget never sees the
/// value: `cornice.fetch` goes out already authenticated.
public struct CredentialRule: Codable, Sendable, Equatable {
    public let host: String
    public let header: String
    public let prefix: String
    public let service: String
    public let account: String

    public init(
        host: String,
        header: String = "Authorization",
        prefix: String = "Bearer ",
        service: String,
        account: String
    ) {
        self.host = host
        self.header = header
        self.prefix = prefix
        self.service = service
        self.account = account
    }
}

// MARK: - Manifest

/// The contract. `apiVersion` is checked by the host before a widget is mounted.
public struct WidgetManifest: Sendable, Equatable {
    public static let currentAPIVersion = 1

    public let id: WidgetID
    public let name: String
    public let version: SemanticVersion
    public let apiVersion: Int
    public let capabilities: Set<Capability>
    /// Hosts this widget may talk to. Required when declaring `.network`.
    public let networkHosts: [String]
    /// Keychain services this widget may read. Required when declaring `.keychain`.
    public let keychainServices: [String]
    /// Secrets the host may attach to outgoing requests on the widget's behalf.
    public let credentials: [CredentialRule]
    /// Fields the widget wants rendered in Options.
    public let settings: [WidgetSetting]
    public let placement: Placement
    public let refresh: RefreshPolicy

    public init(
        id: WidgetID,
        name: String,
        version: SemanticVersion,
        apiVersion: Int = WidgetManifest.currentAPIVersion,
        capabilities: Set<Capability> = [],
        networkHosts: [String] = [],
        keychainServices: [String] = [],
        credentials: [CredentialRule] = [],
        settings: [WidgetSetting] = [],
        placement: Placement,
        refresh: RefreshPolicy = .manual
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.capabilities = capabilities
        self.networkHosts = networkHosts
        self.keychainServices = keychainServices
        self.credentials = credentials
        self.settings = settings
        self.placement = placement
        self.refresh = refresh
    }

    /// Structural problems that should stop a widget from being mounted.
    public var problems: [String] {
        var problems: [String] = []
        if id.isEmpty { problems.append("id is empty") }
        if !id.contains(".") { problems.append("id should be reverse-DNS") }
        if name.isEmpty { problems.append("name is empty") }
        if apiVersion != WidgetManifest.currentAPIVersion {
            problems.append("apiVersion \(apiVersion) is not supported")
        }
        if placement.size.columns < 1 || placement.size.rows < 1 {
            problems.append("placement must be at least 1x1")
        }
        if capabilities.contains(.network) && networkHosts.isEmpty {
            problems.append("network capability requires networkHosts")
        }
        if capabilities.contains(.keychain) && keychainServices.isEmpty {
            problems.append("keychain capability requires keychainServices")
        }
        let settingIDs = settings.map(\.id)
        if Set(settingIDs).count != settingIDs.count {
            problems.append("setting ids must be unique")
        }
        for setting in settings where setting.id.isEmpty || setting.title.isEmpty {
            problems.append("settings need an id and a title")
        }
        for credential in credentials {
            if credential.header.isEmpty {
                problems.append("credential header is empty")
            }
            if !capabilities.contains(.keychain) {
                problems.append("credentials require the keychain capability")
            }
            if !keychainServices.contains(credential.service) {
                problems.append("credential service '\(credential.service)' is not in keychainServices")
            }
            if !networkHosts.contains(where: { $0.caseInsensitiveCompare(credential.host) == .orderedSame }) {
                problems.append("credential host '\(credential.host)' is not in networkHosts")
            }
        }
        return problems
    }
}
