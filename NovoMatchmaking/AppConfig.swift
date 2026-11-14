import SwiftUI

/// Central place for everything you are likely to want to change.
enum AppConfig {
    /// The page the app opens on.
    static let homeURL = URL(string: "https://www.hknovo.com")!

    /// hknovo.com and every subdomain (www., m., api., …) open inside the app.
    static let trustedDomain = "hknovo.com"

    /// Other sites that must stay *inside* the app when the page navigates to them
    /// in the main window – e.g. a payment gateway or "Sign in with Google" page
    /// that redirects back to hknovo.com afterwards. Add hosts here as needed,
    /// e.g. "checkout.stripe.com", "accounts.google.com".
    /// Everything else (WhatsApp, Instagram, Facebook, other websites) opens in
    /// the matching app or in Safari.
    static let extraInAppHosts: Set<String> = []

    /// How much to tighten the space hknovo.com leaves under its footer menu for
    /// the iPhone home indicator (points). The website adds that space plus its
    /// own padding, which looks too tall in an app. 0 = website's own spacing;
    /// raise it to move the footer lower, lower it if labels touch the home bar.
    static let footerTightening: CGFloat = 20

    /// Appended to the WebKit user agent so the website can detect the app,
    /// e.g. `navigator.userAgent.includes("NovoMatchmakingApp")`.
    static var userAgentSuffix: String { "Mobile/15E148 NovoMatchmakingApp/\(appVersion)" }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static func isTrusted(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return isTrusted(host: host)
    }

    static func isTrusted(host rawHost: String) -> Bool {
        let host = rawHost.lowercased()
        return host == trustedDomain || host.hasSuffix("." + trustedDomain)
    }

    static func staysInApp(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return isTrusted(host: host) || extraInAppHosts.contains(host)
    }
}

extension Color {
    static let novoBurgundy = Color(red: 0.35, green: 0.02, blue: 0.13)
    static let novoGold = Color(red: 0.80, green: 0.68, blue: 0.45)
}
