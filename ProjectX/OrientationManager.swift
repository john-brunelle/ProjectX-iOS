import UIKit

// ─────────────────────────────────────────────
// Orientation Manager
//
// Locks the app to portrait, landscape, or auto
// based on user preference. Persisted via
// @AppStorage("pref_orientationLock").
// ─────────────────────────────────────────────

enum OrientationManager {

    /// The currently allowed orientations. Read by AppDelegate.
    static var supportedOrientations: UIInterfaceOrientationMask = .all

    /// Applies the orientation preference and forces a rotation if needed.
    static func apply(_ lock: String) {
        switch lock {
        case "portrait":
            supportedOrientations = .portrait
        case "landscape":
            supportedOrientations = .landscape
        default:
            supportedOrientations = .all
        }

        // Force UIKit to re-evaluate supported orientations
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: supportedOrientations))
        }

        // Tell the app to re-query supportedInterfaceOrientations
        UIViewController.attemptRotationToDeviceOrientation()
    }

    /// Call on app launch to apply the saved preference.
    static func restoreFromDefaults() {
        let lock = UserDefaults.standard.string(forKey: "pref_orientationLock") ?? "auto"
        apply(lock)
    }
}
