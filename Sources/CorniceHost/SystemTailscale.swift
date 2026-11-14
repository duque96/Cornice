import Foundation
import CorniceKit

/// Talks to the Tailscale CLI shipped with the macOS app.
///
/// Only `status`, `up` and `down` are exposed: no arbitrary shell.
public struct SystemTailscale: TailscaleControlling {
    private let binary: URL?

    public init(binary: URL? = SystemTailscale.locateBinary()) {
        self.binary = binary
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
        let fileManager = FileManager.default
        let resolved = url.resolvingSymlinksInPath()

        guard fileManager.isExecutableFile(atPath: resolved.path),
              let attributes = try? fileManager.attributesOfItem(atPath: resolved.path),
              let owner = attributes[.ownerAccountID] as? NSNumber,
              let permissions = attributes[.posixPermissions] as? NSNumber
        else { return false }

        guard (attributes[.type] as? FileAttributeType) == .typeRegular else { return false }

        let currentUser = Int(getuid())
        guard owner.intValue == 0 || owner.intValue == currentUser else { return false }

        // No group/other write: another local user must not be able to replace it.
        return (permissions.intValue & 0o022) == 0
    }

    public func status() async -> TailscaleStatus? {
        guard case .success(let output) = await run(["status", "--json"], timeout: 6) else {
            return nil
        }
        return Self.parse(Data(output.utf8))
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

    private func run(_ arguments: [String], timeout: TimeInterval) async -> Result<String, TailscaleError> {
        guard let binary else { return .failure(.unavailable) }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = binary
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(.commandFailed(error.localizedDescription)))
                    return
                }

                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    usleep(50_000)
                }

                if process.isRunning {
                    process.terminate()
                    continuation.resume(returning: .failure(.timedOut))
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(output))
                } else {
                    let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(
                        returning: .failure(.commandFailed(message.isEmpty ? "exit \(process.terminationStatus)" : message))
                    )
                }
            }
        }
    }
}
