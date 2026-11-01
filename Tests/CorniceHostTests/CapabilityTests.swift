import XCTest
@testable import CorniceHost
@testable import CorniceKit

final class CapabilityTests: XCTestCase {
    private struct FakeKeychain: KeychainAccessing {
        let values: [String: String]

        func secret(service: String, account: String) -> String? {
            values["\(service)/\(account)"]
        }
    }

    func testPolicyAllowsExactHostAndSubdomains() {
        let allowed: Set<String> = ["example.com"]

        XCTAssertTrue(HostPolicy.isAllowed("example.com", in: allowed))
        XCTAssertTrue(HostPolicy.isAllowed("api.example.com", in: allowed))
        XCTAssertTrue(HostPolicy.isAllowed("OPENCODE.AI", in: allowed))
    }

    func testPolicyRejectsLookalikesAndOthers() {
        let allowed: Set<String> = ["example.com"]

        XCTAssertFalse(HostPolicy.isAllowed("evilexample.com", in: allowed))
        XCTAssertFalse(HostPolicy.isAllowed("example.com.evil.com", in: allowed))
        XCTAssertFalse(HostPolicy.isAllowed("example.com", in: allowed))
    }

    func testRateLimiterBlocksOverTheLimit() {
        var limiter = RateLimiter(limit: 2, window: 60)
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertTrue(limiter.allow(now: now))
        XCTAssertTrue(limiter.allow(now: now.addingTimeInterval(1)))
        XCTAssertFalse(limiter.allow(now: now.addingTimeInterval(2)))

        // The window slides.
        XCTAssertTrue(limiter.allow(now: now.addingTimeInterval(61)))
    }

    func testScopedKeychainOnlyAnswersForDeclaredServices() {
        let fake = FakeKeychain(values: [
            "com.duque.cornice/opencode-api-key": "secret",
            "other.app/api-key": "nope",
        ])
        let scoped = ScopedKeychain(base: fake, allowedServices: ["com.duque.cornice"])

        XCTAssertEqual(scoped.secret(service: "com.duque.cornice", account: "opencode-api-key"), "secret")
        XCTAssertNil(scoped.secret(service: "other.app", account: "api-key"))
    }
}
