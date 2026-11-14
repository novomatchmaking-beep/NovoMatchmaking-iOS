import UIKit
import SwiftUI
import UserNotifications

// MARK: - App entry point

@main
struct NovoMatchmakingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)   // the website is designed for light mode
        }
    }
}

// MARK: - Status bar (time, signal, Wi-Fi, battery)

enum StatusBar {
    /// Dark icons on a light header, white icons on a dark header.
    /// Uses app-wide status bar styling (`UIViewControllerBasedStatusBarAppearance = NO`
    /// in Info.plist), which works with SwiftUI's standard window.
    @MainActor
    static func adapt(to background: UIColor) {
        let style: UIStatusBarStyle = background.isDark ? .lightContent : .darkContent
        let app = UIApplication.shared
        if app.statusBarStyle != style {
            app.statusBarStyle = style
        }
    }
}

extension UIColor {
    /// True when white text/icons are easier to read on this colour.
    var isDark: Bool {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.6
    }
}

// MARK: - App delegate (push notifications)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // If the user already allowed notifications, re-register on every launch
        // (Apple can rotate the device token).
        Task { @MainActor in await PushManager.shared.refreshStatus() }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    // Show banners while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // Tapping a notification whose payload contains "url" opens that page.
    // Example APNs payload: {"aps":{"alert":"You have a new match!"},"url":"https://www.hknovo.com/matches"}
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["url"] as? String
        if let raw, let url = URL(string: raw) {
            Task { @MainActor in PushManager.shared.pendingURL = url }
        }
        completionHandler()
    }
}
