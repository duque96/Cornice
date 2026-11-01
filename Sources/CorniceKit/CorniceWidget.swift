import SwiftUI

/// Read access to the Keychain, granted to widgets that declare `.keychain`.
public protocol KeychainAccessing: Sendable {
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
    public let keychain: (any KeychainAccessing)?
    public let log: WidgetLog
    /// Panel width the host is giving the stage, so widgets can size themselves.
    public let availableWidth: CGFloat

    public init(
        capabilities: Set<Capability>,
        keychain: (any KeychainAccessing)?,
        log: WidgetLog,
        availableWidth: CGFloat
    ) {
        self.capabilities = capabilities
        self.keychain = keychain
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
    static var manifest: WidgetManifest { get }
    init(context: WidgetContext)
    func makeView() -> AnyView
    func activate()
    func deactivate()
    func tick(_ now: Date)
}

@MainActor
public protocol WidgetFactory {
    static var manifest: WidgetManifest { get }
    static func make(context: WidgetContext) -> any CorniceWidget
}
