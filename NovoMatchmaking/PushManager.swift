import UIKit
import Combine
import UserNotifications

/// Tracks notification permission and the APNs device token.
///
/// The token is handed to the website (see `WebViewModel.injectPushToken`),
/// so the hknovo.com backend can store it against the logged-in member and
/// send pushes through APNs.
@MainActor
final class PushManager: ObservableObject {
    static let shared = PushManager()

    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    /// A page to open because the user tapped a notification.
    @Published var pendingURL: URL?

    private init() {}

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
        if isEnabled {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    var isEnabled: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshStatus()
        return granted
    }

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
    }

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    }
}
