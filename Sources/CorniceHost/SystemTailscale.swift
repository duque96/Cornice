import Darwin
import Foundation
import CorniceKit

/// Talks to the Tailscale CLI shipped with the macOS app.
///
/// Only `status`, `up` and `down` are exposed: no arbitrary shell.
public struct SystemTailscale: TailscaleControlling {
    /// Injected executable (tests). When nil the CLI is located on every call, so
    /// a binary installed after launch is picked up instead of caching the miss.
    private let explicitBinary: URL?

    public init(binary: URL? = nil) {
        self.explicitBinary = binary
    }

    public static func locateBinary() -> URL? {
        // Prefer the app bundle (root-owned); the Homebrew shim is user-writable.
        let candidates = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { isTrustedExecutable($0) }
    }

    /// Rejects binaries writable by other users or owned by somebody else.
    static func isTrustedExecutable(_ url: URL) -> Bool {
        TrustedExecutable.isTrusted(url)
    }

    private func resolveBinary() -> URL? {
        if let explicitBinary {
            return SystemTailscale.isTrustedExecutable(explicitBinary) ? explicitBinary : nil
        }
        return SystemTailscale.locateBinary()
    }

    public func status() async -> TailscaleStatus? {
        if case .success(let status) = await statusDetailed() { return status }
        return nil
    }

    public func statusDetailed() async -> Result<TailscaleStatus, TailscaleError> {
        if case .success(let status) = await statusOnce() { return .success(status) }
        // One retry: the daemon may be restarting, or the CLI may have been
        // replaced by an update. A second miss is reported with its reason.
        try? await Task.sleep(for: .milliseconds(250))
        return await statusOnce()
    }

    private func statusOnce() async -> Result<TailscaleStatus, TailscaleError> {
        let result = await run(["status", "--json"], timeout: 6)

        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let output):
            // The macOS CLI can exit 0 with a human-readable error instead of JSON
            // (e.g. when its control channel to the GUI/extension is broken).
            guard let parsed = Self.parse(Data(output.utf8)) else {
                let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.commandFailed(message.isEmpty ? "Unexpected CLI output" : message))
            }
            return .success(parsed)
        }
    }

    public func setEnabled(_ enabled: Bool) async -> Result<Void, TailscaleError> {
        switch await run([enabled ? "up" : "down"], timeout: enabled ? 30 : 20) {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Split out so the wire format can be tested without the CLI.
    static func parse(_ data: Data) -> TailscaleStatus? {
        struct SelfInfo: Decodable { let HostName: String? }
        struct Peer: Decodable { let Online: Bool? }
        struct Payload: Decodable {
            let Version: String?
            let BackendState: String?
            let TailscaleIPs: [String]?
            let Peer: [String: Peer]?
            let `Self`: SelfInfo?
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let state = payload.BackendState
        else { return nil }

        let peers = payload.Peer ?? [:]

        return TailscaleStatus(
            backendState: state,
            hostname: payload.Self?.HostName,
            ip: payload.TailscaleIPs?.first,
            peersOnline: peers.values.filter { $0.Online == true }.count,
            peersTotal: peers.count,
            version: payload.Version
        )
    }

    // MARK: - Process

    /// `do shell script` needs the command as an AppleScript string literal.
    static func appleScript(for binary: URL, arguments: [String]) -> String {
        let command = ([binary.path] + arguments)
            .map(shellQuoted)
            .joined(separator: " ")
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\""
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func run(_ arguments: [String], timeout: TimeInterval) async -> Result<String, TailscaleError> {
        guard let binary = resolveBinary() else { return .failure(.unavailable) }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                let outputURL = fileManager.temporaryDirectory
                    .appendingPathComponent("cornice-tailscale-\(UUID().uuidString).out")
                let errorURL = fileManager.temporaryDirectory
                    .appendingPathComponent("cornice-tailscale-\(UUID().uuidString).err")
                fileManager.createFile(atPath: outputURL.path, contents: nil)
                fileManager.createFile(atPath: errorURL.path, contents: nil)
                defer {
                    try? fileManager.removeItem(at: outputURL)
                    try? fileManager.removeItem(at: errorURL)
                }

                // Files instead of pipes: a chatty CLI can't fill a pipe buffer and
                // stall forever, and stderr never contaminates the JSON on stdout.
                guard let outputHandle = try? FileHandle(forWritingTo: outputURL),
                      let errorHandle = try? FileHandle(forWritingTo: errorURL)
                else {
                    continuation.resume(returning: .failure(.commandFailed("Could not capture CLI output")))
                    return
                }

                // Run through osascript: a direct child of a LaunchAgent stalls
                // inside LaunchServices when the CLI tries to reach its GUI,
                // while `do shell script` executes in a working context.
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", SystemTailscale.appleScript(for: binary, arguments: arguments)]
                process.standardOutput = outputHandle
                process.standardError = errorHandle

                do {
                    try process.run()
                } catch {
                    try? outputHandle.close()
                    try? errorHandle.close()
                    continuation.resume(returning: .failure(.commandFailed(error.localizedDescription)))
                    return
                }

                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    usleep(50_000)
                }

                if process.isRunning {
                    process.terminate()
                    let grace = Date().addingTimeInterval(1)
                    while process.isRunning && Date() < grace {
                        usleep(20_000)
                    }
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                    try? outputHandle.close()
                    try? errorHandle.close()
                    continuation.resume(returning: .failure(.timedOut))
                    return
                }

                try? outputHandle.close()
                try? errorHandle.close()

                let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(output))
                } else {
                    let errorOutput = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
                    let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(
                        returning: .failure(.commandFailed(message.isEmpty ? "exit \(process.terminationStatus)" : message))
                    )
                }
            }
        }
    }
}
