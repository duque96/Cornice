import SwiftUI

/// Read access to the Keychain, granted to widgets that declare `.keychain`.
public protocol SecretAccessing: Sendable {
    func secret(service: String, account: String) -> String?
}

// MARK: - Tailscale

public struct TailscaleStatus: Codable, Sendable, Equatable {
    /// BackendState as reported by the CLI: Running, Stopped, NeedsLogin, Starting…
    public let backendState: String
    public let hostname: String?
    public let ip: String?
    public let peersOnline: Int
    public let peersTotal: Int
    public let version: String?

    public init(
        backendState: String,
        hostname: String? = nil,
        ip: String? = nil,
        peersOnline: Int = 0,
        peersTotal: Int = 0,
        version: String? = nil
    ) {
        self.backendState = backendState
        self.hostname = hostname
        self.ip = ip
        self.peersOnline = peersOnline
        self.peersTotal = peersTotal
        self.version = version
    }

    public var isConnected: Bool { backendState == "Running" }
}

public enum TailscaleError: LocalizedError, Sendable, Equatable {
    case unavailable
    case timedOut
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Tailscale CLI not found"
        case .timedOut: return "Tailscale did not answer in time"
        case .commandFailed(let message): return message
        }
    }
}

public protocol TailscaleControlling: Sendable {
    func status() async -> TailscaleStatus?
    func setEnabled(_ enabled: Bool) async -> Result<Void, TailscaleError>
}

public struct WidgetLog: Sendable {
    public let subsystem: String

    public init(subsystem: String) {
        self.subsystem = subsystem
    }

    public func warn(_ message: String) {
        guard ProcessInfo.processInfo.environment["CORNICE_DEBUG"] == "1" else { return }
        FileHandle.standardError.write(Data("[widget:\(subsystem)] \(message)\n".utf8))
    }
}

/// Everything a widget gets from the host. Nothing else is reachable.
@MainActor
public struct WidgetContext {
    public let capabilities: Set<Capability>
    /// `nil` when the widget did not declare `.keychain`.
    public let secrets: (any SecretAccessing)?
    /// `nil` when the widget did not declare `.network`.
    public let http: (any HTTPClient)?
    /// Resolved settings (defaults merged with what the user saved).
    public let settings: WidgetSettings
    /// Language the host is running in.
    public let language: WidgetLanguage
    /// `nil` when the widget did not declare `.tailscale`.
    public let tailscale: (any TailscaleControlling)?
    public let log: WidgetLog
    /// Panel width the host is giving the stage, so widgets can size themselves.
    public let availableWidth: CGFloat

    public init(
        capabilities: Set<Capability>,
        secrets: (any SecretAccessing)?,
        http: (any HTTPClient)?,
        settings: WidgetSettings,
        language: WidgetLanguage,
        tailscale: (any TailscaleControlling)?,
        log: WidgetLog,
        availableWidth: CGFloat
    ) {
        self.capabilities = capabilities
        self.secrets = secrets
        self.http = http
        self.settings = settings
        self.language = language
        self.tailscale = tailscale
        self.log = log
        self.availableWidth = availableWidth
    }
}

/// A widget is a small, self-contained piece of UI plus its own data fetching.
///
/// The host owns the clock: `tick` is called once per second while the surface is
/// visible, and never while it is hidden.
@MainActor
public protocol CorniceWidget: AnyObject {
    func makeView() -> AnyView
    func activate()
    func deactivate()
    func tick(_ now: Date)
}

/// Turns a manifest into a live widget. Instance based so widgets that come from
/// disk (where the manifest is only known at runtime) fit the same contract.
@MainActor
public protocol WidgetFactory {
    var manifest: WidgetManifest { get }
    func make(context: WidgetContext) -> any CorniceWidget
}
