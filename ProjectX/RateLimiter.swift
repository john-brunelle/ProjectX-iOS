import Foundation

// ─────────────────────────────────────────────
// Rate Limiter (Token-Bucket Governor)
//
// Throttles outgoing API requests to stay within
// server-enforced rate limits. Two buckets:
//   • bars  — 45 slots / 30s  (90% of 50 limit)
//   • other — 180 slots / 60s (90% of 200 limit)
//
// Controlled by the "Enable Rate Limiter" toggle
// in Preferences (pref_enableRateLimiter).
// ─────────────────────────────────────────────

actor RateLimiter {

    static let shared = RateLimiter()

    enum Bucket {
        case bars
        case other
    }

    // Capacity set to 90% of server limits to leave headroom
    private let barsCapacity  = 45
    private let barsWindow: TimeInterval = 30

    private let otherCapacity = 180
    private let otherWindow: TimeInterval = 60

    private var barsTimestamps:  [Date] = []
    private var otherTimestamps: [Date] = []

    /// Acquires a slot in the given bucket, waiting if necessary.
    /// Returns immediately if the rate limiter is disabled.
    func acquire(bucket: Bucket) async {
        // Check if governor is enabled
        let enabled = UserDefaults.standard.bool(forKey: "pref_enableRateLimiter")
        guard enabled else { return }

        let capacity: Int
        let window: TimeInterval

        switch bucket {
        case .bars:
            capacity = barsCapacity
            window   = barsWindow
        case .other:
            capacity = otherCapacity
            window   = otherWindow
        }

        while true {
            let now = Date()
            let cutoff = now.addingTimeInterval(-window)

            // Prune expired timestamps
            switch bucket {
            case .bars:
                barsTimestamps.removeAll { $0 < cutoff }
                if barsTimestamps.count < capacity {
                    barsTimestamps.append(now)
                    return
                }
                // Wait until the oldest entry expires
                let waitUntil = barsTimestamps.first!.addingTimeInterval(window)
                let delay = waitUntil.timeIntervalSince(now) + 0.05  // small buffer
                try? await Task.sleep(for: .seconds(max(0.05, delay)))

            case .other:
                otherTimestamps.removeAll { $0 < cutoff }
                if otherTimestamps.count < capacity {
                    otherTimestamps.append(now)
                    return
                }
                let waitUntil = otherTimestamps.first!.addingTimeInterval(window)
                let delay = waitUntil.timeIntervalSince(now) + 0.05
                try? await Task.sleep(for: .seconds(max(0.05, delay)))
            }
        }
    }

    /// Classifies an API path into the appropriate bucket.
    static func bucket(for path: String) -> Bucket {
        path.contains("/api/History/retrieveBars") ? .bars : .other
    }
}
