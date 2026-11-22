import Darwin
import Foundation
import CorniceKit

/// Runs Apple's `networkQuality` tool, which ships with macOS.
///
/// Two processes instead of one (`-s`): the download figure can be painted
/// while the upload phase is still running.
public actor SystemSpeedTest: SpeedTestControlling {
    /// Injected executable (tests). When nil the tool is located on every call.
    private let explicitBinary: URL?
    private let resultsURL: URL?
    private let log = WidgetLog(subsystem: "speedtest")

    private var cached: SpeedTestReport?
    private var cachedLoaded = false

    private var isRunning = false
    private var cancelled = false
    private var activeProcess: Process?

    public init(binary: URL? = nil, resultsURL: URL? = WidgetPaths.speedTestResultsURL) {
        self.explicitBinary = binary
        self.resultsURL = resultsURL
    }

    public static func locateBinary() -> URL? {
        let url = URL(fileURLWithPath: "/usr/bin/networkQuality")
        return TrustedExecutable.isTrusted(url) ? url : nil
    }

    private func resolveBinary() -> URL? {
        if let explicitBinary {
            return TrustedExecutable.isTrusted(explicitBinary) ? explicitBinary : nil
        }
        return SystemSpeedTest.locateBinary()
    }

    // MARK: - SpeedTestControlling

    public func run(
        duration: TimeInterval,
        progress: (@Sendable (SpeedTestProgress) -> Void)?
    ) async -> Result<SpeedTestReport, SpeedTestError> {
        guard !isRunning else { return .failure(.busy) }
        guard resolveBinary() != nil else { return .failure(.unavailable) }

        isRunning = true
        cancelled = false
        defer {
            isRunning = false
            cancelled = false
            activeProcess = nil
        }

        // A widget setting decides the duration, but the host owns the bounds:
        // a manifest cannot ask for an unbounded transfer.
        let seconds = min(max(duration.rounded(), 3), 30)
        let startedAt = Date()

        progress?(.phase(.download))
        let download: SpeedTestMeasurement
        switch await measure(.download, seconds: seconds) {
        case .success(let measurement): download = measurement
        case .failure(let error): return .failure(error)
        }
        progress?(.measured(download))

        if cancelled { return .failure(.cancelled) }

        progress?(.phase(.upload))
        let upload: SpeedTestMeasurement
        switch await measure(.upload, seconds: seconds) {
        case .success(let measurement): upload = measurement
        case .failure(let error): return .failure(error)
        }
        progress?(.measured(upload))

        if cancelled { return .failure(.cancelled) }

        let report = SpeedTestReport(
            download: download,
            upload: upload,
            startedAt: startedAt,
            finishedAt: Date()
        )
        save(report)
        return .success(report)
    }

    public func last() async -> SpeedTestReport? {
        if let cached { return cached }
        guard !cachedLoaded else { return nil }
        cachedLoaded = true

        guard let resultsURL,
              let data = FileManager.default.contents(atPath: resultsURL.path)
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        cached = try? decoder.decode(SpeedTestReport.self, from: data)
        return cached
    }

    public func cancel() async {
        guard isRunning, let process = activeProcess, process.isRunning else { return }
        cancelled = true
        stop(process)
    }

    // MARK: - Phases

    private func measure(
        _ phase: SpeedTestPhase,
        seconds: Double
    ) async -> Result<SpeedTestMeasurement, SpeedTestError> {
        // `-u` means "do not upload" and `-d` "do not download": each run covers
        // exactly one direction.
        let skip = phase == .download ? "-u" : "-d"
        let arguments = [skip, "-M", String(Int(seconds)), "-c"]

        switch await execute(arguments, timeout: seconds + 20) {
        case .failure(let error):
            return .failure(error)
        case .success(let output):
            guard let measurement = SystemSpeedTest.parse(Data(output.utf8), phase: phase) else {
                let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.commandFailed(
                    message.isEmpty ? "Unexpected networkQuality output" : String(message.prefix(200))
                ))
            }
            return .success(measurement)
        }
    }

    /// Split out so the wire format can be tested without running the tool.
    static func parse(
        _ data: Data,
        phase: SpeedTestPhase,
        measuredAt: Date = Date()
    ) -> SpeedTestMeasurement? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let throughputKey = phase == .download ? "dl_throughput" : "ul_throughput"
        let capacityKey = phase == .download ? "downlink_capacity_mbps" : "uplink_capacity_mbps"
        let responsivenessKey = phase == .download ? "dl_responsiveness" : "ul_responsiveness"
        let rpmKey = phase == .download ? "downlink_responsiveness_rpm" : "uplink_responsiveness_rpm"

        // Older builds report bits per second; newer ones also add a Mbps field.
        let bitsPerSecond: Double?
        if let value = number(object[throughputKey]) {
            bitsPerSecond = value
        } else if let mbps = number(object[capacityKey]) {
            bitsPerSecond = mbps * 1_000_000
        } else {
            bitsPerSecond = nil
        }

        guard let bitsPerSecond, bitsPerSecond > 0 else { return nil }

        return SpeedTestMeasurement(
            phase: phase,
            bitsPerSecond: bitsPerSecond,
            latencyMilliseconds: number(object["base_rtt"]),
            responsiveness: number(object[responsivenessKey]) ?? number(object[rpmKey]),
            interfaceName: interfaceName(in: object),
            endpoint: object["test_endpoint"] as? String,
            measuredAt: measuredAt
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func interfaceName(in object: [String: Any]) -> String? {
        if let name = object["interface_name"] as? String, !name.isEmpty {
            return name
        }
        if let interfaces = object["interfaces"] as? [[String: Any]],
           let name = interfaces.first?["interface_name"] as? String,
           !name.isEmpty {
            return name
        }
        return nil
    }

    // MARK: - Process

    private func execute(
        _ arguments: [String],
        timeout: TimeInterval
    ) async -> Result<String, SpeedTestError> {
        guard let binary = resolveBinary() else { return .failure(.unavailable) }

        let fileManager = FileManager.default
        let token = UUID().uuidString
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("cornice-speedtest-\(token).json")
        let errorURL = fileManager.temporaryDirectory
            .appendingPathComponent("cornice-speedtest-\(token).err")
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.removeItem(at: errorURL)
        }

        // Files instead of pipes: the JSON includes large sample arrays and a
        // full pipe buffer would stall the tool.
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL)
        else {
            return .failure(.commandFailed("Could not capture test output"))
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            try? outputHandle.close()
            try? errorHandle.close()
            return .failure(.commandFailed(error.localizedDescription))
        }

        activeProcess = process
        let deadline = Date().addingTimeInterval(timeout)

        while process.isRunning {
            if cancelled || Task.isCancelled {
                stop(process)
                try? outputHandle.close()
                try? errorHandle.close()
                return .failure(.cancelled)
            }
            if Date() >= deadline {
                stop(process)
                try? outputHandle.close()
                try? errorHandle.close()
                log.warn("networkQuality timed out")
                return .failure(.timedOut)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        activeProcess = nil
        try? outputHandle.close()
        try? errorHandle.close()

        // A terminate() racing with a clean exit still counts as a cancellation.
        if cancelled { return .failure(.cancelled) }

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        if process.terminationStatus == 0 {
            return .success(output)
        }

        let errorOutput = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(.commandFailed(message.isEmpty ? "exit \(process.terminationStatus)" : message))
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()

        let grace = Date().addingTimeInterval(1)
        while process.isRunning && Date() < grace {
            usleep(20_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    // MARK: - Persistence

    private func save(_ report: SpeedTestReport) {
        cached = report
        cachedLoaded = true

        guard let resultsURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            try FileManager.default.createDirectory(
                at: resultsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(report).write(to: resultsURL, options: .atomic)
        } catch {
            log.warn("could not save speed test: \(error.localizedDescription)")
        }
    }
}

public extension WidgetPaths {
    static var speedTestResultsURL: URL {
        supportDirectory.appendingPathComponent("speedtest.json")
    }
}
