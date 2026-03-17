import Foundation
import SwiftData
import SwiftUI

// ─────────────────────────────────────────────
// AccountProfile — SwiftData Model
//
// Stores user-customizable metadata for an API
// account (alias nickname). Keyed by accountId
// since Account is a Codable struct from the API.
// ─────────────────────────────────────────────

@Model
final class AccountProfile {
    var accountId: Int
    var alias: String

    init(accountId: Int, alias: String = "") {
        self.accountId = accountId
        self.alias     = alias
    }
}

// ─────────────────────────────────────────────
// AccountAvatar — Deterministic Identicon
//
// Generates a unique, reproducible avatar from
// an account ID. Uses a 5×5 symmetric grid with
// a hue-derived color — no network, no assets.
// ─────────────────────────────────────────────

struct AccountAvatar: View {
    let accountId: Int
    var size: CGFloat = 44

    // Splitmix64 — great distribution for small sequential integers
    private var seed: UInt64 {
        var x = UInt64(bitPattern: Int64(accountId)) &+ 0x9e3779b97f4a7c15
        x = (x ^ (x >> 30)) &* 0xbf58476d1ce4e5b9
        x = (x ^ (x >> 27)) &* 0x94d049bb133111eb
        return x ^ (x >> 31)
    }

    private var avatarColor: Color {
        Color(hue: Double(seed % 360) / 360.0, saturation: 0.58, brightness: 0.82)
    }

    // Symmetric: col 3 mirrors col 1, col 4 mirrors col 0
    private func cellOn(row: Int, col: Int) -> Bool {
        let bit = row * 3 + min(col, 4 - col)
        return (seed >> bit) & 1 == 1
    }

    var body: some View {
        Canvas { ctx, sz in
            let pad  = sz.width * 0.14
            let cell = (sz.width - pad * 2) / 5
            for row in 0..<5 {
                for col in 0..<5 {
                    guard cellOn(row: row, col: col) else { continue }
                    let gap: CGFloat = cell * 0.08
                    let rect = CGRect(
                        x: pad + CGFloat(col) * cell + gap,
                        y: pad + CGFloat(row) * cell + gap,
                        width:  cell - gap * 2,
                        height: cell - gap * 2
                    )
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: cell * 0.22),
                        with: .color(avatarColor)
                    )
                }
            }
        }
        .background(avatarColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .frame(width: size, height: size)
    }
}
