import Foundation
import WebKit

/// Network lockdown for widget pages.
///
/// A `WKWebView` happily lets a page call `fetch`, load `<img>` or execute
/// `<script src>` against any host. That would bypass the manifest allow-list
/// (and could exfiltrate settings or run remote code inside the page).
///
/// This content rule list blocks **every** network load from the page. The only
/// way out is `cornice.fetch`, which goes through the host client with its
/// allow-list, rate limit and credential injection.
@MainActor
enum WidgetContentRules {
    nonisolated static let rulesJSON = """
    [
      { "trigger": { "url-filter": "^https?://" }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "^wss?://" }, "action": { "type": "block" } },
      { "trigger": { "url-filter": "^ftp://" }, "action": { "type": "block" } }
    ]
    """

    private static var compiled: WKContentRuleList?
    private static var waiting: [@MainActor (WKContentRuleList?) -> Void] = []

    /// Compiles once and hands the list to every caller. If compilation fails the
    /// list is `nil` and callers must refuse to load the page (fail closed).
    static func prepare(_ completion: @escaping @MainActor (WKContentRuleList?) -> Void) {
        if let compiled {
            completion(compiled)
            return
        }

        waiting.append(completion)
        guard waiting.count == 1 else { return }

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "cornice-network-block-v1",
            encodedContentRuleList: rulesJSON
        ) { list, error in
            if let error {
                FileHandle.standardError.write(
                    Data("[widgets] content rules failed: \(error)\n".utf8)
                )
            }

            let box = RuleListBox(list)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    compiled = box.list
                    let callbacks = waiting
                    waiting = []
                    callbacks.forEach { $0(box.list) }
                }
            }
        }
    }
}

private final class RuleListBox: @unchecked Sendable {
    let list: WKContentRuleList?

    init(_ list: WKContentRuleList?) {
        self.list = list
    }
}
