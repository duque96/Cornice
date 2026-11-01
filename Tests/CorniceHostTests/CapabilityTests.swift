import XCTest
@testable import CorniceHost
@testable import CorniceKit

final class CapabilityTests: XCTestCase {
    private struct FakeSecrets: SecretAccessing {
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

    func testScopedSecretsOnlyAnswersForDeclaredServices() {
        let fake = FakeSecrets(values: [
            "com.duque.cornice/opencode-api-key": "secret",
            "other.app/api-key": "nope",
        ])
        let scoped = ScopedSecrets(base: fake, allowedServices: ["com.duque.cornice"])

        XCTAssertEqual(scoped.secret(service: "com.duque.cornice", account: "opencode-api-key"), "secret")
        XCTAssertNil(scoped.secret(service: "other.app", account: "api-key"))
    }

    // MARK: - Credential injection

    private func credentialSource(secret: String? = "sk-test") -> CredentialSource {
        let keychain = FakeSecrets(values: secret.map { ["com.duque.cornice/opencode-api-key": $0] } ?? [:])
        return CredentialSource(
            rule: CredentialRule(
                host: "example.com",
                header: "Authorization",
                prefix: "Bearer ",
                service: "com.duque.cornice",
                account: "opencode-api-key"
            ),
            secrets: keychain
        )
    }

    func testCredentialsAreInjectedForTheDeclaredHost() {
        let headers = CredentialInjector.apply([:], host: "example.com", sources: [credentialSource()])

        XCTAssertEqual(headers["Authorization"], "Bearer sk-test")
    }

    func testCredentialsAreInjectedForSubdomains() {
        let headers = CredentialInjector.apply([:], host: "api.example.com", sources: [credentialSource()])

        XCTAssertEqual(headers["Authorization"], "Bearer sk-test")
    }

    func testCredentialsNeverLeaveTheDeclaredHost() {
        let headers = CredentialInjector.apply([:], host: "example.com", sources: [credentialSource()])

        XCTAssertTrue(headers.isEmpty)
    }

    func testWidgetHeadersWinOverInjectedCredentials() {
        let headers = CredentialInjector.apply(
            ["Authorization": "Bearer custom"],
            host: "example.com",
            sources: [credentialSource()]
        )

        XCTAssertEqual(headers["Authorization"], "Bearer custom")
    }

    func testMissingSecretInjectsNothing() {
        let headers = CredentialInjector.apply([:], host: "example.com", sources: [credentialSource(secret: nil)])

        XCTAssertTrue(headers.isEmpty)
    }
}
