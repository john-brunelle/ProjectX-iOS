import SwiftUI

// ─────────────────────────────────────────────
// BotAvatar — Deterministic Geometric Avatar
//
// Generates a unique, reproducible avatar from
// a UUID using concentric ring segments — visually
// distinct from the grid-based AccountAvatar.
// ─────────────────────────────────────────────

struct BotAvatar: View {
    let botId: UUID
    var size: CGFloat = 44

    // Derive a stable UInt64 seed from the UUID
    private var seed: UInt64 {
        let (a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p) = botId.uuid
        var x = UInt64(a) | UInt64(b) << 8 | UInt64(c) << 16 | UInt64(d) << 24
            | UInt64(e) << 32 | UInt64(f) << 40 | UInt64(g) << 48 | UInt64(h) << 56
        x ^= UInt64(i) | UInt64(j) << 8 | UInt64(k) << 16 | UInt64(l) << 24
            | UInt64(m) << 32 | UInt64(n) << 40 | UInt64(o) << 48 | UInt64(p) << 56
        // Splitmix64 finalizer
        x = (x ^ (x >> 30)) &* 0xbf58476d1ce4e5b9
        x = (x ^ (x >> 27)) &* 0x94d049bb133111eb
        return x ^ (x >> 31)
    }

    private var hue: Double {
        Double(seed % 360) / 360.0
    }

    private var baseColor: Color {
        Color(hue: hue, saturation: 0.55, brightness: 0.80)
    }

    private var accentColor: Color {
        Color(hue: (hue + 0.35).truncatingRemainder(dividingBy: 1.0), saturation: 0.50, brightness: 0.75)
    }

    /// 3 rings, each divided into segments. A bit is read from the seed
    /// to decide whether each segment is filled with the base or accent color.
    private func segmentOn(ring: Int, segment: Int) -> Bool {
        let bit = ring * 8 + segment
        return (seed >> (bit % 64)) & 1 == 1
    }

    var body: some View {
        Canvas { ctx, sz in
            let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let maxRadius = sz.width / 2

            // Center dot
            let dotRadius = maxRadius * 0.18
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - dotRadius, y: center.y - dotRadius,
                    width: dotRadius * 2, height: dotRadius * 2
                )),
                with: .color(baseColor)
            )

            // 3 concentric rings with increasing segment counts
            let rings: [(innerFrac: CGFloat, outerFrac: CGFloat, segments: Int)] = [
                (0.22, 0.42, 6),
                (0.45, 0.68, 8),
                (0.71, 0.95, 10),
            ]

            for (ringIndex, ring) in rings.enumerated() {
                let innerR = maxRadius * ring.innerFrac
                let outerR = maxRadius * ring.outerFrac
                let gap = Angle(degrees: 2)

                for seg in 0..<ring.segments {
                    let segAngle = Angle(degrees: 360.0 / Double(ring.segments))
                    let start = Angle(degrees: Double(seg) * segAngle.degrees) + gap
                    let end = Angle(degrees: Double(seg + 1) * segAngle.degrees) - gap

                    var path = Path()
                    path.addArc(center: center, radius: outerR,
                                startAngle: start, endAngle: end, clockwise: false)
                    path.addArc(center: center, radius: innerR,
                                startAngle: end, endAngle: start, clockwise: true)
                    path.closeSubpath()

                    let color = segmentOn(ring: ringIndex, segment: seg) ? baseColor : accentColor
                    ctx.fill(path, with: .color(color.opacity(segmentOn(ring: ringIndex, segment: seg) ? 1.0 : 0.45)))
                }
            }
        }
        .background(baseColor.opacity(0.10))
        .clipShape(Circle())
        .frame(width: size, height: size)
    }
}
