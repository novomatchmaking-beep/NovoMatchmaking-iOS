import SwiftUI
import WebKit

struct NovoWebView: UIViewRepresentable {
    let model: WebViewModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.applicationNameForUserAgent = AppConfig.userAgentSuffix
        config.websiteDataStore = .default()   // keeps members logged in between launches

        // Lets the website know it is running inside the app, and lets it call
        // window.webkit.messageHandlers.novo.postMessage({ action: "requestPush" })
        let bootstrap = "window.NovoApp = Object.assign(window.NovoApp || {}, { platform: 'ios', version: '\(AppConfig.appVersion)' });"
        config.userContentController.addUserScript(
            WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(WeakScriptMessageHandler(context.coordinator), name: "novo")

        let webView = NovoWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        // hknovo.com already leaves room for the home indicator under its footer
        // (CSS safe-area insets). Don't add a second gap on top of that.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }  // Safari ▸ Develop menu
        #endif

        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(Color.novoBurgundy)
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pulledToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        model.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "novo")
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let model: WebViewModel

        init(model: WebViewModel) { self.model = model }

        @objc func pulledToRefresh(_ sender: UIRefreshControl) {
            model.reload()
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            // nil target frame = a new window (target="_blank"); treat like the main frame.
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

            switch scheme {
            case "http", "https":
                if !isMainFrame || AppConfig.staysInApp(url) {
                    // Embedded content (maps, videos, reCAPTCHA, payment widgets)
                    // and hknovo.com pages load normally.
                    decisionHandler(.allow)
                } else {
                    // Other websites: open in their own app (WhatsApp, Instagram…) or Safari.
                    decisionHandler(.cancel)
                    UIApplication.shared.open(url)
                }
            case "about", "blob", "data", "javascript", "":
                decisionHandler(.allow)
            default:
                // tel:, mailto:, sms:, whatsapp:, maps:, itms-apps: …
                decisionHandler(.cancel)
                if navigationAction.navigationType == .linkActivated || isMainFrame {
                    UIApplication.shared.open(url)
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.navigationStarted()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            model.navigationFinished()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            model.navigationFailed(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            model.navigationFailed(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            model.renderingProcessTerminated()
        }

        // MARK: New windows (target="_blank", window.open)

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if AppConfig.staysInApp(url) {
                    webView.load(navigationAction.request)
                } else {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        // MARK: JavaScript alert / confirm / prompt

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            guard let presenter = presenter(for: webView) else { completionHandler(); return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            presenter.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            guard let presenter = presenter(for: webView) else { completionHandler(false); return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            presenter.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            guard let presenter = presenter(for: webView) else { completionHandler(nil); return }
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                completionHandler(alert?.textFields?.first?.text)
            })
            presenter.present(alert, animated: true)
        }

        // MARK: Camera / microphone for the website (e.g. video calls, profile photos)

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            // hknovo.com is trusted, so skip WebKit's extra prompt; iOS still asks once.
            decisionHandler(AppConfig.isTrusted(host: origin.host) ? .grant : .prompt)
        }

        // MARK: Messages from the website

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard AppConfig.isTrusted(host: message.frameInfo.securityOrigin.host),
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }
            switch action {
            case "requestPush":
                Task { @MainActor [model] in
                    await PushManager.shared.requestAuthorization()
                    model.injectPushToken()
                }
            default:
                break
            }
        }

        private func presenter(for webView: WKWebView) -> UIViewController? {
            var top = webView.window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }
    }
}

/// Avoids the retain cycle WKUserContentController creates with its message handlers.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Tells the website the home-indicator area is slightly smaller than it is
/// (CSS `env(safe-area-inset-bottom)`), so the site's footer menu sits snugly
/// at the bottom like a native tab bar instead of floating high.
final class NovoWKWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        var insets = super.safeAreaInsets
        insets.bottom = max(0, insets.bottom - AppConfig.footerTightening)
        return insets
    }
}
