import Foundation
import CorniceKit

/// Secrets at rest in Application Support, one file per service/account, mode 0600.
///
/// It replaces the Keychain on purpose: ad-hoc signed builds change their code
/// signature on every rebuild, which makes macOS re-prompt for access to Keychain
/// items. A 0600 file has the same threat model as the plain file this app already
/// imported (`~/.config/example-usage/key`) and keeps the widget sandbox intact:
/// only the host reads it.
public struct FileSecretStore: SecretAccessing {
    public let root: URL

    public init(root: URL = WidgetPaths.secretsDirectory) {
        self.root = root
    }

    public func secret(service: String, account: String) -> String? {
        guard let url = fileURL(service: service, account: account),
              let data = FileManager.default.contents(atPath: url.path),
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func save(service: String, account: String, value: String) throws {
        guard let url = fileURL(service: service, account: account) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data(value.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func delete(service: String, account: String) {
        guard let url = fileURL(service: service, account: account) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func fileURL(service: String, account: String) -> URL? {
        let safeService = sanitize(service)
        let safeAccount = sanitize(account)
        guard !safeService.isEmpty, !safeAccount.isEmpty else { return nil }

        return root
            .appendingPathComponent(safeService, isDirectory: true)
            .appendingPathComponent(safeAccount, isDirectory: false)
    }

    private func sanitize(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
                ? character
                : "_"
        }
        .map(String.init)
        .joined()
    }
}

public extension WidgetPaths {
    static var secretsDirectory: URL {
        supportDirectory.appendingPathComponent("secrets", isDirectory: true)
    }
}
