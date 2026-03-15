import SwiftUI
import Lottie

// ─────────────────────────────────────────────
// SplashView
//
// Cold start splash screen with:
//   - Lottie candlestick chart animation
//   - App name fade-in
//   - Tagline fade-in
//   - Smooth transition to main app
//
// The splash shows for the duration of the
// Lottie animation (3 seconds), then fades out.
// ─────────────────────────────────────────────

struct SplashView: View {
    @Binding var isShowingSplash: Bool

    @State private var titleOpacity:   Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var splashOpacity:  Double = 1

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.15),
                    Color(red: 0.02, green: 0.04, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Lottie Animation ──────────
                LottieView(animationName: "trading_splash") {
                    // Animation complete callback
                    beginDismiss()
                }
                .frame(width: 280, height: 280)

                // ── App Name ──────────────────
                VStack(spacing: 8) {
                    Text("ProjectX")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(titleOpacity)

                    Text("Professional Futures Trading")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(red: 0.18, green: 0.8, blue: 0.44))
                        .opacity(taglineOpacity)
                }
                .padding(.top, 24)

                Spacer()

                // ── Bottom branding ───────────
                Text("Powered by ProjectX Gateway API")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 40)
                    .opacity(taglineOpacity)
            }
        }
        .opacity(splashOpacity)
        .onAppear {
            // Staggered fade-ins
            withAnimation(.easeIn(duration: 0.6).delay(0.4)) {
                titleOpacity = 1
            }
            withAnimation(.easeIn(duration: 0.6).delay(0.8)) {
                taglineOpacity = 1
            }
        }
    }

    private func beginDismiss() {
        withAnimation(.easeInOut(duration: 0.5).delay(0.3)) {
            splashOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isShowingSplash = false
        }
    }
}

// ─────────────────────────────────────────────
// LottieView — SwiftUI wrapper for Lottie
// ─────────────────────────────────────────────

struct LottieView: UIViewRepresentable {
    let animationName: String
    var onComplete: (() -> Void)?

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: animationName)
        view.contentMode = .scaleAspectFit
        view.loopMode    = .playOnce
        view.animationSpeed = 1.0
        view.play { finished in
            if finished { onComplete?() }
        }
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {}
}
