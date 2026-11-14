import XCTest
@testable import CorniceHost
@testable import CorniceKit

final class RedirectPolicyTests: XCTestCase {
    private let allowed: Set<String> = ["example.com"]

    func testAllowsTheHostAndItsSubdomains() {
        XCTAssertTrue(RedirectPolicy.allows(URL(string: "https://example.com/a")!, allowedHosts: allowed))
        XCTAssertTrue(RedirectPolicy.allows(URL(string: "https://api.example.com/a")!, allowedHosts: allowed))
    }

    func testRejectsAnythingElse() {
        XCTAssertFalse(RedirectPolicy.allows(URL(string: "https://other.test/a")!, allowedHosts: allowed))
        XCTAssertFalse(RedirectPolicy.allows(URL(string: "https://evilexample.com/a")!, allowedHosts: allowed))
        XCTAssertFalse(RedirectPolicy.allows(URL(string: "file:///etc/passwd")!, allowedHosts: allowed))
    }

    func testSameHostKeepsCredentials() {
        let headers = ["Authorization": "Bearer a", "X-Token": "b", "Accept": "text/plain"]

        let result = RedirectPolicy.headers(
            headers,
            from: "example.com",
            to: "example.com",
            credentialHeaders: ["Authorization", "X-Token"]
        )

        XCTAssertEqual(result, headers)
    }

    func testCrossHostStripsCredentialsAndCookies() {
        let headers = [
            "Authorization": "Bearer a",
            "X-Token": "b",
            "Cookie": "session=1",
            "Accept": "text/plain",
        ]

        let result = RedirectPolicy.headers(
            headers,
            from: "example.com",
            to: "api.example.com",
            credentialHeaders: ["Authorization", "X-Token"]
        )

        XCTAssertNil(result["Authorization"])
        XCTAssertNil(result["X-Token"])
        XCTAssertNil(result["Cookie"])
        XCTAssertEqual(result["Accept"], "text/plain")
    }
}

final class WidgetContentRulesTests: XCTestCase {
    func testRulesBlockEveryNetworkScheme() throws {
        let data = Data(WidgetContentRules.rulesJSON.utf8)
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )

        let filters = rules.compactMap {
            ($0["trigger"] as? [String: Any])?["url-filter"] as? String
        }
        let actions = rules.compactMap { $0["action"] as? [String: Any] }

        XCTAssertEqual(filters, ["^https?://", "^wss?://", "^ftp://"])
        XCTAssertTrue(actions.allSatisfy { $0["type"] as? String == "block" })
    }
}


private final class HugeBodyProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "50000"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 50_000))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class WidgetHTTPClientTests: XCTestCase {
    func testRejectsOversizedResponses() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HugeBodyProtocol.self]

        let client = WidgetHTTPClient(
            allowedHosts: ["example.com"],
            log: WidgetLog(subsystem: "test"),
            maxResponseBytes: 1_000,
            session: URLSession(configuration: configuration)
        )

        do {
            _ = try await client.send(HTTPRequest(url: URL(string: "https://example.com/big")!))
            XCTFail("Expected responseTooLarge")
        } catch let error as HTTPError {
            XCTAssertEqual(error, .responseTooLarge)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
