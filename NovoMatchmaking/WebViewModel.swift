import SwiftUI
import Combine
import WebKit
import Network

@MainActor
final class WebViewModel: ObservableObject {

    enum Problem: Equatable {
        case offline
        case loadFailed(detail: String)
        case emptyPage
        case renderingStopped
    }

    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var isLoading = true
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published var problem: Problem?
    /// A page change failed but the previous page is still on screen:
    /// show a small "tap to retry" message instead of a full error screen.
    @Published var showConnectionBanner = false
    /// Colour at the top of the page; decides whether the status bar icons are dark or white.
    @Published private(set) var headerColor: UIColor = .white

    private(set) weak var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []
    private var queuedURL: URL?
    private var lastFailedURL: URL?
    private var renderingRestarts = 0
    private var quietRetries = 0

    private let pathMonitor = NWPathMonitor()
    private var isOnline = true

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.novo.matchmaking.network"))
    }

    deinit {
        pathMonitor.cancel()
    }

    // MARK: - Web view lifecycle

    func attach(_ webView: WKWebView) {
        guard self.webView !== webView else { return }
        self.webView = webView
        observations = [
            webView.observe(\.estimatedProgress) { [weak self] _, _ in
                Task { @MainActor in self?.syncFromWebView() }
            },
            webView.observe(\.canGoBack) { [weak self] _, _ in
                Task { @MainActor in self?.syncFromWebView() }
            },
            webView.observe(\.isLoading) { [weak self] _, _ in
                Task { @MainActor in self?.syncFromWebView() }
            },
            // Single-page sites change the address without a full reload:
            // re-check the top colour once when that happens (not while scrolling).
            webView.observe(\.url) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    self?.sampleHeaderColor()
                }
            }
        ]
        let first = queuedURL ?? AppConfig.homeURL
        queuedURL = nil
        load(first)
    }

    private func syncFromWebView() {
        guard let webView else { return }
        progress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        isLoading = webView.isLoading
    }

    // MARK: - Actions

    var currentURL: URL {
        if let url = webView?.url, url.scheme?.hasPrefix("http") == true { return url }
        return AppConfig.homeURL
    }

    func load(_ url: URL) {
        guard let webView else {
            queuedURL = url   // web view not created yet – load it as soon as it is
            return
        }
        problem = nil
        isLoading = true
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    func goHome() { load(AppConfig.homeURL) }

    func goBack() { webView?.goBack() }

    func reload() {
        if problem != nil || webView?.url == nil {
            retry()
        } else {
            webView?.reload()
        }
    }

    /// Try the page that failed again. If the same page fails twice in a row,
    /// fall back to the home page so the user is never stuck on an error.
    func retry() {
        if let failed = lastFailedURL, quietRetries < 2 {
            load(failed)
        } else {
            quietRetries = 0
            lastFailedURL = nil
            goHome()
        }
    }

    func openInSafari() {
        UIApplication.shared.open(lastFailedURL ?? currentURL)
    }

    // MARK: - Navigation events (called by NovoWebView.Coordinator)

    func navigationStarted() {
        isLoading = true
    }

    func navigationFinished() {
        hasLoadedOnce = true
        problem = nil
        lastFailedURL = nil
        showConnectionBanner = false
        renderingRestarts = 0
        quietRetries = 0
        syncFromWebView()
        checkForEmptyPage()
        injectPushToken()
        sampleHeaderColor()
        // Pages that build their header with JavaScript may paint it a moment later.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self?.sampleHeaderColor()
            try? await Task.sleep(nanoseconds: 900_000_000)
            self?.sampleHeaderColor()
        }
    }

    func navigationFailed(_ error: Error) {
        let e = error as NSError
        // Cancelled navigations are normal (a new link was tapped, or we opened it elsewhere).
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        // 102 = "Frame load interrupted": we cancelled it in the policy delegate / a download.
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return }

        lastFailedURL = e.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? webView?.url

        // Brief network hiccups (address lookup, timeout, dropped connection) usually
        // clear up within a second or two, so retry quietly before showing an error.
        let transientCodes = [NSURLErrorCannotFindHost, NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
                              NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed]
        if e.domain == NSURLErrorDomain && transientCodes.contains(e.code) && quietRetries < 2 && isOnline {
            quietRetries += 1
            let delay = Double(quietRetries) * 1.5
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, let url = self.lastFailedURL else { return }
                self.load(url)
            }
            return
        }

        isLoading = false

        // A page is already showing: keep it on screen and offer a quick retry
        // rather than covering everything with an error.
        if hasLoadedOnce && problem == nil && webView?.url != nil {
            showConnectionBanner = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self?.showConnectionBanner = false
            }
            return
        }

        let offlineCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                            NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff]
        if e.domain == NSURLErrorDomain && (offlineCodes.contains(e.code) || !isOnline) {
            problem = .offline
        } else {
            let host = lastFailedURL?.host ?? ""
            problem = .loadFailed(detail: "\(e.localizedDescription) (\(e.code)) \(host)")
        }
    }

    func renderingProcessTerminated() {
        // Usually caused by memory pressure while the app was in the background.
        // Reload quietly a couple of times before bothering the user.
        if renderingRestarts < 2, let webView {
            renderingRestarts += 1
            if webView.url != nil { webView.reload() } else { goHome() }
        } else {
            isLoading = false
            problem = .renderingStopped
        }
    }

    // MARK: - Helpers

    private func networkChanged(online: Bool) {
        let cameBackOnline = online && !isOnline
        isOnline = online
        if cameBackOnline && (problem != nil || showConnectionBanner) {
            showConnectionBanner = false
            retry()
        }
    }

    /// Flags a page that rendered nothing at all (usually a hosting / server problem).
    private func checkForEmptyPage() {
        let js = "({text:((document.body&&document.body.innerText)||'').trim().length,html:(document.documentElement?document.documentElement.innerHTML.length:0)})"
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            let info = result as? [String: Any]
            let textLength = (info?["text"] as? NSNumber)?.intValue ?? -1
            let htmlLength = (info?["html"] as? NSNumber)?.intValue ?? -1
            Task { @MainActor in
                if textLength == 0 && htmlLength >= 0 && htmlLength < 500 {
                    self?.problem = .emptyPage
                }
            }
        }
    }

    /// Samples the colour at the top of the page once per page load (not while
    /// scrolling, which kept the app busy). It tints the status-bar area and
    /// decides whether the time / signal / battery icons are dark or white.
    func sampleHeaderColor() {
        guard let webView, webView.bounds.width > 0, hasLoadedOnce else { return }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: webView.bounds.width, height: 4)
        config.snapshotWidth = NSNumber(value: 48)
        config.afterScreenUpdates = false
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let color = image?.averageColor else { return }
            Task { @MainActor in
                guard let self, !self.headerColor.isClose(to: color) else { return }
                self.headerColor = color
            }
        }
    }

    /// Gives the APNs token to hknovo.com so its backend can send push notifications.
    /// The website can read it from `window.NovoApp.pushToken`, from
    /// `localStorage.novoPushToken`, or listen for the `novo:push-token` event.
    func injectPushToken() {
        guard let token = PushManager.shared.deviceToken,
              token.allSatisfy({ $0.isHexDigit }),
              let webView, let url = webView.url, AppConfig.isTrusted(url) else { return }
        let js = """
        (function(t){
          window.NovoApp = window.NovoApp || {};
          window.NovoApp.pushToken = t;
          try { localStorage.setItem('novoPushToken', t); } catch (e) {}
          window.dispatchEvent(new CustomEvent('novo:push-token', { detail: { token: t, platform: 'ios' } }));
        })('\(token)');
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

extension UIImage {
    /// Average colour of the whole image.
    var averageColor: UIColor? {
        guard let cg = cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn, pixel[3] > 0 else { return nil }
        let alpha = CGFloat(pixel[3]) / 255
        return UIColor(red: min(1, CGFloat(pixel[0]) / 255 / alpha),
                       green: min(1, CGFloat(pixel[1]) / 255 / alpha),
                       blue: min(1, CGFloat(pixel[2]) / 255 / alpha),
                       alpha: 1)
    }
}

extension UIColor {
    /// Ignores tiny differences so scrolling doesn't cause needless redraws.
    func isClose(to other: UIColor) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return false }
        return abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2) < 0.02
    }
}
