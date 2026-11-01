import SwiftUI

/// Read access to the Keychain, granted to widgets that declare `.keychain`.
public protocol SecretAccessing: Sendable {
    func secret(service: String, account: String) -> String?
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
    public let log: WidgetLog
    /// Panel width the host is giving the stage, so widgets can size themselves.
    public let availableWidth: CGFloat

    public init(
        capabilities: Set<Capability>,
        secrets: (any SecretAccessing)?,
        http: (any HTTPClient)?,
        settings: WidgetSettings,
        language: WidgetLanguage,
        log: WidgetLog,
        availableWidth: CGFloat
    ) {
        self.capabilities = capabilities
        self.secrets = secrets
        self.http = http
        self.settings = settings
        self.language = language
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
