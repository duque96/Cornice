import Foundation
import CorniceKit

/// Redirect policy for widget requests.
///
/// `URLSession` follows redirects by default, so checking only the original URL
/// would let an allowed host bounce the client to any other host. These helpers
/// keep the check pure and testable; `WidgetRedirectGuard` applies them.
enum RedirectPolicy {
    static func allows(_ url: URL, allowedHosts: Set<String>) -> Bool {
        guard let host = url.host else { return false }
        return HostPolicy.isAllowed(host, in: allowedHosts)
    }

    /// Cross-host redirects never keep credentials.
    static func headers(
        _ headers: [String: String],
        from originalHost: String?,
        to newHost: String?,
        credentialHeaders: Set<String>
    ) -> [String: String] {
        guard originalHost?.caseInsensitiveCompare(newHost ?? "") != .orderedSame else {
            return headers
        }

        var cleaned = headers
        for header in credentialHeaders {
            cleaned.removeValue(forKey: header)
        }
        cleaned.removeValue(forKey: "Cookie")
        cleaned.removeValue(forKey: "Authorization")
        return cleaned
    }
}

/// URLSession delegate that stops redirects to hosts outside the allow-list.
final class WidgetRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHosts: Set<String>
    private let credentialHeaders: Set<String>
    private let log: WidgetLog

    init(allowedHosts: Set<String>, credentialHeaders: Set<String>, log: WidgetLog) {
        self.allowedHosts = allowedHosts
        self.credentialHeaders = credentialHeaders
        self.log = log
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, RedirectPolicy.allows(url, allowedHosts: allowedHosts) else {
            log.warn("blocked redirect to \(request.url?.host ?? "?")")
            completionHandler(nil)
            return
        }

        var forwarded = request
        let originalHost = task.originalRequest?.url?.host
        if originalHost?.caseInsensitiveCompare(url.host ?? "") != .orderedSame {
            for header in credentialHeaders {
                forwarded.setValue(nil, forHTTPHeaderField: header)
            }
            forwarded.setValue(nil, forHTTPHeaderField: "Cookie")
            forwarded.setValue(nil, forHTTPHeaderField: "Authorization")
        }

        completionHandler(forwarded)
    }
}
