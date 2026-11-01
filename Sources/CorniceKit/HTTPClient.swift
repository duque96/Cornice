import Foundation

// MARK: - Wire types

public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var timeout: TimeInterval

    public init(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        timeout: TimeInterval = 15
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.timeout = timeout
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
}

// MARK: - Client

/// The only way a widget may reach the network. The host injects an implementation
/// that enforces the hosts and rate limit declared in the manifest.
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public enum HTTPError: LocalizedError, Equatable, Sendable {
    case hostNotAllowed(String)
    case rateLimited
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .hostNotAllowed(let host):
            return "Network access to \(host) is not allowed"
        case .rateLimited:
            return "Too many requests"
        case .transport(let message):
            return message
        }
    }
}
