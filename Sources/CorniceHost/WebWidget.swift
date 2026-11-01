import AppKit
import WebKit
import SwiftUI
import CorniceKit

/// A widget loaded from disk: a folder with a manifest and an HTML page.
///
/// It runs in a WKWebView, so it cannot reach the file system, the Keychain or the
/// network on its own. Everything goes through the host bridge.
@MainActor
final class WebWidget: CorniceWidget {
    private let content: WebWidgetContent

    init(bundle: DiskWidget, context: WidgetContext) {
        self.content = WebWidgetContent(bundle: bundle, context: context)
    }

    func makeView() -> AnyView {
        AnyView(WebWidgetView(webView: content.webView))
    }

    func activate() {}

    func deactivate() {}

    func tick(_ now: Date) {
        content.sendTick(now)
    }
}

struct WebWidgetView: NSViewRepresentable {
    let webView: WKWebView

    /// A container with Auto Layout constraints: resizing the cell resizes the
    /// WKWebView, which makes the page reflow. Returning the web view directly kept
    /// it laid out at its initial width.
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Bridge

@MainActor
final class WebWidgetContent: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView

    private let bundle: DiskWidget
    private let http: (any HTTPClient)?
    private let settings: WidgetSettings
    private let language: WidgetLanguage
    private let tailscale: (any TailscaleControlling)?
    private let log: WidgetLog

    init(bundle: DiskWidget, context: WidgetContext) {
        self.bundle = bundle
        self.http = context.http
        self.settings = context.settings
        self.language = context.language
        self.tailscale = context.tailscale
        self.log = context.log

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        configuration.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        controller.add(self, name: "cornice")
        controller.addUserScript(
            WKUserScript(
                source: Self.bridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.addUserScript(
            WKUserScript(
                source: Self.settingsScript(context.settings, context.language),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.addUserScript(
            WKUserScript(
                source: Self.styleScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        log.warn("settings \(context.settings.values)")
        webView.loadFileURL(bundle.entry, allowingReadAccessTo: bundle.directory)
    }

    func sendTick(_ date: Date) {
        let millis = date.timeIntervalSince1970 * 1000
        webView.callAsyncJavaScript(
            "window.__corniceTick(ts)",
            arguments: ["ts": millis],
            in: nil,
            in: .page
        ) { _ in }
    }

    // MARK: Navigation

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              url.isFileURL,
              navigationAction.targetFrame != nil,
              PathContainment.contains(bundle.directory, url.standardizedFileURL)
        else {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.warn("page loaded \(bundle.manifest.id)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.warn("page failed \(bundle.manifest.id): \(error.localizedDescription)")
    }

    // MARK: Messages

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "cornice",
              let body = message.body as? [String: Any],
              let id = body["id"] as? Int,
              let method = body["method"] as? String
        else { return }

        let params = body["params"] as? [String: Any] ?? [:]

        switch method {
        case "fetch":
            handleFetch(id: id, params: params)
        case "tailscale.status":
            handleTailscaleStatus(id: id)
        case "tailscale.set":
            handleTailscaleSet(id: id, enabled: params["enabled"] as? Bool ?? false)
        default:
            respond(id: id, payload: ["ok": false, "error": "Unknown method '\(method)'"])
        }
    }

    private func handleFetch(id: Int, params: [String: Any]) {
        guard let urlString = params["url"] as? String, let url = URL(string: urlString) else {
            respond(id: id, payload: ["ok": false, "error": "Invalid URL"])
            return
        }
        guard let http else {
            respond(id: id, payload: ["ok": false, "error": "Network not permitted"])
            return
        }

        let request = HTTPRequest(
            url: url,
            method: params["method"] as? String ?? "GET",
            headers: params["headers"] as? [String: String] ?? [:]
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await http.send(request)
                self.log.warn("fetch \(url.host ?? "") -> \(response.status)")
                let text = String(data: response.body, encoding: .utf8) ?? ""
                self.respond(id: id, payload: ["ok": true, "status": response.status, "text": text])
            } catch {
                self.log.warn("fetch failed: \(error.localizedDescription)")
                self.respond(id: id, payload: ["ok": false, "error": error.localizedDescription])
            }
        }
    }

    private func handleTailscaleStatus(id: Int) {
        guard let tailscale else {
            respond(id: id, payload: ["ok": false, "error": "Tailscale not permitted"])
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard let status = await tailscale.status() else {
                self.respond(id: id, payload: ["ok": false, "error": "Tailscale unavailable"])
                return
            }

            self.respond(id: id, payload: [
                "ok": true,
                "status": [
                    "backendState": status.backendState,
                    "hostname": status.hostname ?? "",
                    "ip": status.ip ?? "",
                    "peersOnline": status.peersOnline,
                    "peersTotal": status.peersTotal,
                    "version": status.version ?? "",
                ],
            ])
        }
    }

    private func handleTailscaleSet(id: Int, enabled: Bool) {
        guard let tailscale else {
            respond(id: id, payload: ["ok": false, "error": "Tailscale not permitted"])
            return
        }

        Task { [weak self] in
            guard let self else { return }
            switch await tailscale.setEnabled(enabled) {
            case .success:
                self.log.warn("tailscale \(enabled ? "up" : "down")")
                self.respond(id: id, payload: ["ok": true])
            case .failure(let error):
                self.log.warn("tailscale failed: \(error.localizedDescription)")
                self.respond(id: id, payload: ["ok": false, "error": error.localizedDescription])
            }
        }
    }

    private func respond(id: Int, payload: [String: Any]) {
        webView.callAsyncJavaScript(
            "window.__corniceResolve(id, payload)",
            arguments: ["id": id, "payload": payload],
            in: nil,
            in: .page
        ) { _ in }
    }

    // MARK: Scripts

    private static let bridgeScript = """
    (function () {
      const pending = new Map();
      let nextId = 1;

      function request(method, params) {
        return new Promise((resolve, reject) => {
          const id = nextId++;
          pending.set(id, { resolve, reject });
          window.webkit.messageHandlers.cornice.postMessage({
            id: id,
            method: method,
            params: params || {}
          });
        });
      }

      window.cornice = {
        tailscale: {
          status: function () { return request('tailscale.status', {}); },
          set: function (enabled) { return request('tailscale.set', { enabled: !!enabled }); }
        },
        fetch(url, options) {
          options = options || {};
          return new Promise((resolve, reject) => {
            const id = nextId++;
            pending.set(id, { resolve, reject });
            window.webkit.messageHandlers.cornice.postMessage({
              id: id,
              method: 'fetch',
              params: {
                url: String(url),
                method: options.method || 'GET',
                headers: options.headers || {}
              }
            });
          });
        },
        onTick(callback) {
          window.__corniceTickCallback = callback;
        }
      };

      window.__corniceResolve = function (id, payload) {
        const entry = pending.get(id);
        if (!entry) return;
        pending.delete(id);
        if (payload && payload.ok) {
          entry.resolve({ status: payload.status, text: payload.text });
        } else {
          entry.reject(new Error((payload && payload.error) || 'Request failed'));
        }
      };

      window.__corniceTick = function (ts) {
        if (typeof window.__corniceTickCallback === 'function') {
          window.__corniceTickCallback(ts);
        }
      };
    })();
    """

    private static func settingsScript(_ settings: WidgetSettings, _ language: WidgetLanguage) -> String {
        let payload = settings.values.mapValues(\.jsonObject)
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return """
        window.cornice = window.cornice || {};
        window.cornice.settings = \(json);
        window.cornice.language = "\(language.rawValue)";
        window.cornice.locale = "\(language.localeIdentifier)";
        """
    }

    private static let styleScript = """
    (function () {
      const style = document.createElement('style');
      style.textContent = 'html, body { background: transparent !important; margin: 0; }';
      document.documentElement.appendChild(style);
    })();
    """
}
