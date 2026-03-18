import Foundation
import UserNotifications

// ─────────────────────────────────────────────
// NotificationService — Local Notifications
//
// Fires local notifications for stop-loss hits,
// take-profit hits, order fills, and bot errors.
// Each category is gated by its UserDefaults pref.
// ─────────────────────────────────────────────

@MainActor @Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()

    private(set) var isAuthorized = false

    // Deduplication — prevents re-firing on subsequent poll cycles
    private var notifiedTradeIds: Set<Int> = []
    private var notifiedOrderIds: Set<Int> = []

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - Permission

    func requestPermissionIfNeeded() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .notDetermined else {
                isAuthorized = settings.authorizationStatus == .authorized
                return
            }
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                isAuthorized = granted
            } catch {
                isAuthorized = false
            }
        }
    }

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Foreground Display

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Stop Loss

    func notifyStopLossHit(tradeId: Int, botName: String, pnl: Double, contractId: String) {
        guard UserDefaults.standard.bool(forKey: "pref_notifyOnStopLoss") else { return }
        guard !notifiedTradeIds.contains(tradeId) else { return }
        notifiedTradeIds.insert(tradeId)

        let content = UNMutableNotificationContent()
        content.title = "Stop Loss Hit"
        content.body = "\(botName) on \(contractId) lost $\(String(format: "%.2f", abs(pnl)))"
        content.sound = .default

        schedule(content: content, id: "sl-\(tradeId)")
    }

    // MARK: - Take Profit

    func notifyTakeProfitHit(tradeId: Int, botName: String, pnl: Double, contractId: String) {
        guard UserDefaults.standard.bool(forKey: "pref_notifyOnTakeProfit") else { return }
        guard !notifiedTradeIds.contains(tradeId) else { return }
        notifiedTradeIds.insert(tradeId)

        let content = UNMutableNotificationContent()
        content.title = "Take Profit Hit"
        content.body = "\(botName) on \(contractId) gained $\(String(format: "%.2f", pnl))"
        content.sound = .default

        schedule(content: content, id: "tp-\(tradeId)")
    }

    // MARK: - Order Fill

    func notifyOrderFilled(orderId: Int, side: String, size: Int, contractId: String) {
        guard UserDefaults.standard.bool(forKey: "pref_notifyOnOrderFill") else { return }
        guard !notifiedOrderIds.contains(orderId) else { return }
        notifiedOrderIds.insert(orderId)

        let content = UNMutableNotificationContent()
        content.title = "Order Filled"
        content.body = "\(side) \(size) \(contractId) filled (Order #\(orderId))"
        content.sound = .default

        schedule(content: content, id: "fill-\(orderId)")
    }

    // MARK: - Bot Error

    func notifyBotError(botName: String, message: String) {
        guard UserDefaults.standard.bool(forKey: "pref_notifyOnBotError") else { return }

        let content = UNMutableNotificationContent()
        content.title = "Bot Error"
        content.body = "\(botName): \(message)"
        content.sound = .default

        // Use a unique ID per error instance (no dedup needed — each call is distinct)
        schedule(content: content, id: "err-\(UUID().uuidString)")
    }

    // MARK: - Helpers

    private func schedule(content: UNMutableNotificationContent, id: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
