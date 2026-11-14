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
