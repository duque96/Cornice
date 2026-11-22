import Darwin
import Foundation
import CorniceKit

/// Runs Apple's `networkQuality` tool, which ships with macOS.
///
/// Two processes instead of one (`-s`): the download figure can be painted
/// while the upload phase is still running. Each process gets a pseudo-terminal
/// because the tool only prints its ~2 Hz progress lines when stdout is a TTY.
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
        switch await measure(.download, seconds: seconds, progress: progress) {
        case .success(let measurement): download = measurement
        case .failure(let error): return .failure(error)
        }
        progress?(.measured(download))

        if cancelled { return .failure(.cancelled) }

        progress?(.phase(.upload))
        let upload: SpeedTestMeasurement
        switch await measure(.upload, seconds: seconds, progress: progress) {
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
        seconds: Double,
        progress: (@Sendable (SpeedTestProgress) -> Void)?
    ) async -> Result<SpeedTestMeasurement, SpeedTestError> {
        let fileManager = FileManager.default
        let jsonURL = fileManager.temporaryDirectory
            .appendingPathComponent("cornice-speedtest-\(UUID().uuidString).json")
        defer { try? fileManager.removeItem(at: jsonURL) }

        // `-u` means "do not upload" and `-d` "do not download": each run covers
        // exactly one direction. `-c` only takes an attached filename, and `-v`
        // plus a TTY is what turns the progress stream on.
        let skip = phase == .download ? "-u" : "-d"
        let arguments = [skip, "-M", String(Int(seconds)), "-v", "-c\(jsonURL.path)"]

        if let error = await execute(arguments, timeout: seconds + 20, phase: phase, progress: progress) {
            return .failure(error)
        }

        guard let data = fileManager.contents(atPath: jsonURL.path) else {
            return .failure(.commandFailed("Unexpected networkQuality output"))
        }
        guard let measurement = SystemSpeedTest.parse(data, phase: phase) else {
            return .failure(.commandFailed("Unexpected networkQuality output"))
        }
        return .success(measurement)
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

    /// One line of the verbose stream:
    /// `Downlink: capacity 324.260 Mbps, responsiveness 1050 RPM (…) - Uplink: …`
    static func parseProgressLine(
        _ line: String,
        phase: SpeedTestPhase
    ) -> (bitsPerSecond: Double, responsiveness: Double?)? {
        let cleaned = strippingANSI(line)
        let label = phase == .download ? "Downlink: capacity " : "Uplink: capacity "

        guard let start = cleaned.range(of: label)?.upperBound else { return nil }

        // Read only this direction's section: the other one is on the same line.
        let section = cleaned[start...].components(separatedBy: " - ").first ?? ""
        guard let valueText = section.split(separator: " ").first,
              let mbps = Double(valueText.replacingOccurrences(of: ",", with: ".")),
              mbps > 0
        else { return nil }

        var responsiveness: Double?
        if let rpmStart = section.range(of: "responsiveness ")?.upperBound {
            let tail = section[rpmStart...]
            if let text = tail.split(separator: " ").first,
               let value = Double(text),
               value > 0 {
                responsiveness = value
            }
        }

        return (mbps * 1_000_000, responsiveness)
    }

    static func strippingANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[A-Za-z]",
            with: "",
            options: .regularExpression
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
        timeout: TimeInterval,
        phase: SpeedTestPhase,
        progress: (@Sendable (SpeedTestProgress) -> Void)?
    ) async -> SpeedTestError? {
        guard let binary = resolveBinary() else { return .unavailable }

        let fileManager = FileManager.default
        let token = UUID().uuidString
        let errorURL = fileManager.temporaryDirectory
            .appendingPathComponent("cornice-speedtest-\(token).err")
        fileManager.createFile(atPath: errorURL.path, contents: nil)
        defer { try? fileManager.removeItem(at: errorURL) }

        guard let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            return .commandFailed("Could not capture test output")
        }
        defer { try? errorHandle.close() }

        // Without a TTY the tool stays silent until the JSON is done, so the
        // terminal is only an optimization for the live numbers.
        let terminal = SystemSpeedTest.openPseudoTerminal()
        let stdoutHandle: FileHandle?
        if let terminal {
            stdoutHandle = FileHandle(fileDescriptor: terminal.slave, closeOnDealloc: false)
        } else {
            stdoutHandle = FileHandle(forWritingAtPath: "/dev/null")
        }
        guard let stdoutHandle else {
            if let terminal { close(terminal.master); close(terminal.slave) }
            return .commandFailed("Could not capture test output")
        }
        defer {
            if let terminal { close(terminal.master) }
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            if let terminal { close(terminal.master); close(terminal.slave) }
            return .commandFailed(error.localizedDescription)
        }

        // The child owns its copy of the slave now; ours would keep the pipe open.
        if let terminal { close(terminal.slave) }

        activeProcess = process
        var pending = Data()
        let deadline = Date().addingTimeInterval(timeout)

        while process.isRunning {
            if let terminal {
                SystemSpeedTest.readProgress(
                    from: terminal.master,
                    pending: &pending,
                    phase: phase,
                    progress: progress
                )
            }

            if cancelled || Task.isCancelled {
                stop(process)
                return .cancelled
            }
            if Date() >= deadline {
                stop(process)
                log.warn("networkQuality timed out")
                return .timedOut
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Last lines may arrive between the exit check and now.
        if let terminal {
            SystemSpeedTest.readProgress(
                from: terminal.master,
                pending: &pending,
                phase: phase,
                progress: progress
            )
        }

        activeProcess = nil
        if cancelled || Task.isCancelled { return .cancelled }

        guard process.terminationStatus == 0 else {
            let message = (try? String(contentsOf: errorURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .commandFailed(message.isEmpty ? "exit \(process.terminationStatus)" : message)
        }
        return nil
    }

    /// Reads whatever the tool has written, splits complete lines and forwards
    /// the samples. The stream repaints with `\r`, so both breaks count.
    private static func readProgress(
        from master: Int32,
        pending: inout Data,
        phase: SpeedTestPhase,
        progress: (@Sendable (SpeedTestProgress) -> Void)?
    ) {
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(master, &chunk, chunk.count)
            guard count > 0 else { break }
            pending.append(contentsOf: chunk[0..<count])
        }

        var start = pending.startIndex
        while let end = pending[start...].firstIndex(where: { $0 == 0x0D || $0 == 0x0A }) {
            let line = String(decoding: pending[start..<end], as: UTF8.self)
            start = pending.index(after: end)

            guard let sample = parseProgressLine(line, phase: phase) else { continue }
            progress?(.sample(
                phase,
                bitsPerSecond: sample.bitsPerSecond,
                responsiveness: sample.responsiveness
            ))
        }

        if start > pending.startIndex {
            pending.removeSubrange(pending.startIndex..<start)
        }
        // A stream without breaks must not grow forever.
        if pending.count > 65_536 {
            pending.removeAll()
        }
    }

    private struct PseudoTerminal {
        let master: Int32
        let slave: Int32
    }

    private static func openPseudoTerminal() -> PseudoTerminal? {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0,
              grantpt(master) == 0,
              unlockpt(master) == 0,
              let name = ptsname(master)
        else {
            if master >= 0 { close(master) }
            return nil
        }

        let slave = open(name, O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            close(master)
            return nil
        }

        // The tool renders for a terminal; give it a width it will not wrap at.
        var size = winsize()
        size.ws_row = 50
        size.ws_col = 200
        _ = ioctl(slave, TIOCSWINSZ, &size)

        // Non-blocking so the wait loop can poll the process and the stream.
        let flags = fcntl(master, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        }

        return PseudoTerminal(master: master, slave: slave)
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
