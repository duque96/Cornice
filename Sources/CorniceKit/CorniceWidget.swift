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
    /// Same as `status()` but keeps the reason, so the host can tell "CLI not
    /// installed" apart from "CLI there but not answering".
    func statusDetailed() async -> Result<TailscaleStatus, TailscaleError>
}

public extension TailscaleControlling {
    func statusDetailed() async -> Result<TailscaleStatus, TailscaleError> {
        if let status = await status() { return .success(status) }
        return .failure(.unavailable)
    }
}


// MARK: - Storage

public struct StorageStatus: Codable, Sendable, Equatable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let usedBytes: Int64
    /// Space the cleaner could free with the recommended categories.
    public let recoverableBytes: Int64

    public init(totalBytes: Int64, freeBytes: Int64, usedBytes: Int64, recoverableBytes: Int64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.usedBytes = usedBytes
        self.recoverableBytes = recoverableBytes
    }
}

public protocol StorageControlling: Sendable {
    /// Volume capacity plus a cached estimate of reclaimable cache space.
    func status() async -> StorageStatus?
    /// Opens the native review window. The widget never deletes anything.
    func review() async
}

// MARK: - Speed test

public enum SpeedTestPhase: String, Codable, Sendable, Equatable {
    case download
    case upload
}

/// One phase of a network quality test. Throughput is kept in bits per second,
/// which is what the tool reports; display units are a widget concern.
public struct SpeedTestMeasurement: Codable, Sendable, Equatable {
    public let phase: SpeedTestPhase
    public let bitsPerSecond: Double
    /// Idle round-trip time in milliseconds.
    public let latencyMilliseconds: Double?
    /// Round trips per minute under load.
    public let responsiveness: Double?
    public let interfaceName: String?
    public let endpoint: String?
    public let measuredAt: Date

    public init(
        phase: SpeedTestPhase,
        bitsPerSecond: Double,
        latencyMilliseconds: Double? = nil,
        responsiveness: Double? = nil,
        interfaceName: String? = nil,
        endpoint: String? = nil,
        measuredAt: Date = Date()
    ) {
        self.phase = phase
        self.bitsPerSecond = bitsPerSecond
        self.latencyMilliseconds = latencyMilliseconds
        self.responsiveness = responsiveness
        self.interfaceName = interfaceName
        self.endpoint = endpoint
        self.measuredAt = measuredAt
    }

    public var megabitsPerSecond: Double { bitsPerSecond / 1_000_000 }
}

public struct SpeedTestReport: Codable, Sendable, Equatable {
    public let download: SpeedTestMeasurement?
    public let upload: SpeedTestMeasurement?
    public let startedAt: Date
    public let finishedAt: Date

    public init(
        download: SpeedTestMeasurement?,
        upload: SpeedTestMeasurement?,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.download = download
        self.upload = upload
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

/// Incremental events so the widget can show the download figure while the
/// upload phase is still running.
public enum SpeedTestProgress: Sendable, Equatable {
    case phase(SpeedTestPhase)
    case measured(SpeedTestMeasurement)
}

public enum SpeedTestError: LocalizedError, Sendable, Equatable {
    case unavailable
    /// Another test is already saturating the link.
    case busy
    case cancelled
    case timedOut
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Network quality tool not available"
        case .busy: return "A speed test is already running"
        case .cancelled: return "Speed test cancelled"
        case .timedOut: return "Speed test did not finish in time"
        case .commandFailed(let message): return message
        }
    }
}

public protocol SpeedTestControlling: Sendable {
    /// Runs download and upload in sequence. The host clamps `duration` per
    /// phase; a widget cannot ask for an unbounded transfer.
    func run(
        duration: TimeInterval,
        progress: (@Sendable (SpeedTestProgress) -> Void)?
    ) async -> Result<SpeedTestReport, SpeedTestError>
    /// Last stored report, so a widget can paint figures before running again.
    func last() async -> SpeedTestReport?
    func cancel() async
}

public extension SpeedTestControlling {
    func run(duration: TimeInterval) async -> Result<SpeedTestReport, SpeedTestError> {
        await run(duration: duration, progress: nil)
    }

    func cancel() async {}
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
    /// Rendered widget scale (1.0 = normal).
    public let uiScale: CGFloat
    /// Language the host is running in.
    public let language: WidgetLanguage
    /// `nil` when the widget did not declare `.tailscale`.
    public let tailscale: (any TailscaleControlling)?
    /// `nil` when the widget did not declare `.storage`.
    public let storage: (any StorageControlling)?
    /// `nil` when the widget did not declare `.speedtest`.
    public let speedtest: (any SpeedTestControlling)?
    public let log: WidgetLog
    /// Panel width the host is giving the stage, so widgets can size themselves.
    public let availableWidth: CGFloat

    public init(
        capabilities: Set<Capability>,
        secrets: (any SecretAccessing)?,
        http: (any HTTPClient)?,
        settings: WidgetSettings,
        uiScale: CGFloat,
        language: WidgetLanguage,
        tailscale: (any TailscaleControlling)?,
        storage: (any StorageControlling)?,
        speedtest: (any SpeedTestControlling)?,
        log: WidgetLog,
        availableWidth: CGFloat
    ) {
        self.capabilities = capabilities
        self.secrets = secrets
        self.http = http
        self.settings = settings
        self.uiScale = uiScale
        self.language = language
        self.tailscale = tailscale
        self.storage = storage
        self.speedtest = speedtest
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
