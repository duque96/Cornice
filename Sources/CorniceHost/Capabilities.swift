import Foundation
import CorniceKit

// MARK: - Policy

/// Requests per time window. Pure and testable: the clock is passed in.
public struct RateLimiter: Sendable {
    public let limit: Int
    public let window: TimeInterval
    private var hits: [Date] = []

    public init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    public mutating func allow(now: Date) -> Bool {
        hits.removeAll { now.timeIntervalSince($0) >= window }
        guard hits.count < limit else { return false }
        hits.append(now)
        return true
    }
}

public enum HostPolicy {
    /// `example.com` allows `example.com` and any subdomain, never `notexample.com`.
    public static func isAllowed(_ host: String, in allowed: Set<String>) -> Bool {
        let candidate = host.lowercased()
        return allowed.contains { entry in
            let allowedHost = entry.lowercased()
            return candidate == allowedHost || candidate.hasSuffix("." + allowedHost)
        }
    }
}

// MARK: - Credentials

public struct CredentialSource: Sendable {
    public let rule: CredentialRule
    public let secrets: any SecretAccessing

    public init(rule: CredentialRule, secrets: any SecretAccessing) {
        self.rule = rule
        self.secrets = secrets
    }
}

public enum CredentialInjector {
    /// Adds the declared header for a matching host. Existing headers win.
    public static func apply(
        _ headers: [String: String],
        host: String,
        sources: [CredentialSource]
    ) -> [String: String] {
        var result = headers

        for source in sources where HostPolicy.isAllowed(host, in: [source.rule.host]) {
            guard result[source.rule.header] == nil,
                  let secret = source.secrets.secret(
                    service: source.rule.service,
                    account: source.rule.account
                  )
            else { continue }

            result[source.rule.header] = source.rule.prefix + secret
        }

        return result
    }
}

// MARK: - Client

/// Concrete `HTTPClient` handed to widgets that declare `.network`.
///
/// It is the only place where URLSession is used on behalf of a widget, and it
/// refuses any host the manifest did not declare.
public actor WidgetHTTPClient: HTTPClient {
    private let allowedHosts: Set<String>
    private let credentials: [CredentialSource]
    private let log: WidgetLog
    private let session: URLSession
    private var limiter: RateLimiter

    public init(
        allowedHosts: Set<String>,
        credentials: [CredentialSource] = [],
        requestsPerMinute: Int = 30,
        log: WidgetLog,
        session: URLSession = .shared
    ) {
        self.allowedHosts = allowedHosts
        self.credentials = credentials
        self.log = log
        self.session = session
        self.limiter = RateLimiter(limit: requestsPerMinute, window: 60)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let host = request.url.host else {
            throw HTTPError.hostNotAllowed("?")
        }
        guard HostPolicy.isAllowed(host, in: allowedHosts) else {
            log.warn("blocked request to \(host)")
            throw HTTPError.hostNotAllowed(host)
        }
        guard limiter.allow(now: Date()) else {
            log.warn("rate limited")
            throw HTTPError.rateLimited
        }

        let headers = CredentialInjector.apply(request.headers, host: host, sources: credentials)

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.transport("Invalid response")
            }
            return HTTPResponse(status: http.statusCode, body: data)
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError.transport("Offline")
        }
    }
}

// MARK: - Scoped Keychain

/// Narrows secret access to the services the manifest declared.
public struct ScopedSecrets: SecretAccessing {
    private let base: any SecretAccessing
    private let allowedServices: Set<String>

    public init(base: any SecretAccessing, allowedServices: Set<String>) {
        self.base = base
        self.allowedServices = allowedServices
    }

    public func secret(service: String, account: String) -> String? {
        guard allowedServices.contains(service) else { return nil }
        return base.secret(service: service, account: account)
    }
}
