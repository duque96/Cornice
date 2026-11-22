import Darwin
import Foundation

/// Executables the host runs on a widget's behalf must not be replaceable by
/// another local user.
enum TrustedExecutable {
    /// Rejects binaries writable by other users or owned by somebody else.
    static func isTrusted(_ url: URL) -> Bool {
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
}
