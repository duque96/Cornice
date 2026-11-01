import XCTest
@testable import CorniceKit

final class ManifestContractTests: XCTestCase {
    func testANetworkWidgetMustDeclareHosts() {
        let manifest = WidgetManifest(
            id: "com.example.weather",
            name: "Weather",
            version: SemanticVersion(1, 0, 0),
            capabilities: [.network],
            placement: Placement(size: GridSize(columns: 2, rows: 1))
        )

        XCTAssertTrue(manifest.problems.contains { $0.contains("networkHosts") })
    }

    func testAKeychainWidgetMustDeclareServices() {
        let manifest = WidgetManifest(
            id: "com.example.secrets",
            name: "Secrets",
            version: SemanticVersion(1, 0, 0),
            capabilities: [.keychain],
            placement: Placement(size: GridSize(columns: 2, rows: 1))
        )

        XCTAssertTrue(manifest.problems.contains { $0.contains("keychainServices") })
    }

    func testCredentialsRequireTheKeychainCapability() {
        let manifest = WidgetManifest(
            id: "com.example.api",
            name: "API",
            version: SemanticVersion(1, 0, 0),
            capabilities: [.network],
            networkHosts: ["example.com"],
            credentials: [
                CredentialRule(host: "example.com", service: "svc", account: "acc")
            ],
            placement: Placement(size: GridSize(columns: 2, rows: 1))
        )

        XCTAssertTrue(manifest.problems.contains { $0.contains("keychain capability") })
    }

    func testCredentialsStayInsideTheDeclaredHostsAndServices() {
        let manifest = WidgetManifest(
            id: "com.example.api",
            name: "API",
            version: SemanticVersion(1, 0, 0),
            capabilities: [.network, .keychain],
            networkHosts: ["example.com"],
            keychainServices: ["svc"],
            credentials: [
                CredentialRule(host: "other.com", service: "svc", account: "acc")
            ],
            placement: Placement(size: GridSize(columns: 2, rows: 1))
        )

        XCTAssertTrue(manifest.problems.contains { $0.contains("credential host") })
    }

    func testAWellFormedCredentialManifestHasNoProblems() {
        let manifest = WidgetManifest(
            id: "com.example.api",
            name: "API",
            version: SemanticVersion(1, 0, 0),
            capabilities: [.network, .keychain],
            networkHosts: ["example.com"],
            keychainServices: ["svc"],
            credentials: [
                CredentialRule(host: "example.com", service: "svc", account: "acc")
            ],
            placement: Placement(size: GridSize(columns: 2, rows: 1))
        )

        XCTAssertTrue(manifest.problems.isEmpty, "\(manifest.problems)")
    }

    func testUnsupportedAPIVersionIsRejected() {
        let manifest = WidgetManifest(
            id: "com.example.old",
            name: "Old",
            version: SemanticVersion(1, 0, 0),
            apiVersion: 99,
            placement: Placement(size: GridSize(columns: 1, rows: 1))
        )

        XCTAssertFalse(manifest.problems.isEmpty)
    }

    func testHTTPResponseKnowsSuccess() {
        XCTAssertTrue(HTTPResponse(status: 200, body: Data()).isSuccess)
        XCTAssertTrue(HTTPResponse(status: 204, body: Data()).isSuccess)
        XCTAssertFalse(HTTPResponse(status: 401, body: Data()).isSuccess)
        XCTAssertFalse(HTTPResponse(status: 500, body: Data()).isSuccess)
    }
}
