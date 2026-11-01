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
    private let height: CGFloat

    init(bundle: DiskWidget, context: WidgetContext) {
        self.content = WebWidgetContent(bundle: bundle, context: context)
        self.height = CGFloat(max(1, bundle.manifest.placement.size.rows)) * 28 + 8
    }

    func makeView() -> AnyView {
        AnyView(
            WebWidgetView(webView: content.webView)
                .frame(height: height)
        )
    }

    func activate() {}

    func deactivate() {}

    func tick(_ now: Date) {
        content.sendTick(now)
    }
}

struct WebWidgetView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Bridge

@MainActor
final class WebWidgetContent: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView

    private let bundle: DiskWidget
    private let http: (any HTTPClient)?
    private let log: WidgetLog

    init(bundle: DiskWidget, context: WidgetContext) {
        self.bundle = bundle
        self.http = context.http
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
                source: Self.styleScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
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

        switch method {
        case "fetch":
            handleFetch(id: id, params: body["params"] as? [String: Any] ?? [:])
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
                let text = String(data: response.body, encoding: .utf8) ?? ""
                self.respond(id: id, payload: ["ok": true, "status": response.status, "text": text])
            } catch {
                self.log.warn("fetch failed: \(error.localizedDescription)")
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

      window.cornice = {
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

    private static let styleScript = """
    (function () {
      const style = document.createElement('style');
      style.textContent = 'html, body { background: transparent !important; margin: 0; }';
      document.documentElement.appendChild(style);
    })();
    """
}
