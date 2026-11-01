import Foundation

public typealias WidgetID = String

// MARK: - Version

public struct SemanticVersion: Codable, Sendable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }
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

// MARK: - Manifest

/// The contract. `apiVersion` is checked by the host before a widget is mounted.
public struct WidgetManifest: Sendable, Equatable {
    public static let currentAPIVersion = 1

    public let id: WidgetID
    public let name: String
    public let version: SemanticVersion
    public let apiVersion: Int
    public let capabilities: Set<Capability>
    public let placement: Placement
    public let refresh: RefreshPolicy

    public init(
        id: WidgetID,
        name: String,
        version: SemanticVersion,
        apiVersion: Int = WidgetManifest.currentAPIVersion,
        capabilities: Set<Capability> = [],
        placement: Placement,
        refresh: RefreshPolicy = .manual
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.capabilities = capabilities
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
        return problems
    }
}
