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


final class WidgetBundleSafetyTests: XCTestCase {
    private func makeBundle() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-safe-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("Safe.cornicewidget", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        let manifest = """
        {
          "id": "com.example.safe",
          "name": "Safe",
          "version": "1.0.0",
          "apiVersion": 1,
          "capabilities": [],
          "placement": { "columns": 3, "rows": 2 },
          "entry": "index.html"
        }
        """
        try manifest.write(to: bundle.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: bundle.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        return bundle
    }

    func testRejectsSymlinksInsideABundle() throws {
        let bundle = try makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }

        try FileManager.default.createSymbolicLink(
            at: bundle.appendingPathComponent("leak"),
            withDestinationURL: URL(fileURLWithPath: "/etc/hosts")
        )

        XCTAssertThrowsError(try WidgetBundleStore.load(bundleAt: bundle)) { error in
            guard case DiskWidgetError.unsafeEntry = error else {
                return XCTFail("Expected unsafeEntry, got \(error)")
            }
        }
    }

    func testAcceptsABundleWithRegularFiles() throws {
        let bundle = try makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }

        XCTAssertNoThrow(try WidgetBundleStore.load(bundleAt: bundle))
    }
}

final class TailscaleBinaryTests: XCTestCase {
    private func makeExecutable(_ permissions: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-bin-\(UUID().uuidString)")
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        return url
    }

    func testTrustsAUserOwnedExecutable() throws {
        let url = try makeExecutable(0o755)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(SystemTailscale.isTrustedExecutable(url))
    }

    func testRejectsAGroupWritableExecutable() throws {
        let url = try makeExecutable(0o775)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(SystemTailscale.isTrustedExecutable(url))
    }

    func testRejectsAMissingBinary() {
        XCTAssertFalse(
            SystemTailscale.isTrustedExecutable(
                URL(fileURLWithPath: "/tmp/cornice-missing-\(UUID().uuidString)")
            )
        )
    }

    func testFollowsSymlinks() throws {
        let target = try makeExecutable(0o755)
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("cornice-link-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.removeItem(at: link)
        }

        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertTrue(SystemTailscale.isTrustedExecutable(link))
    }
}
