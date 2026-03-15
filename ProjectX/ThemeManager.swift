import SwiftUI

// ─────────────────────────────────────────────
// App Theme System
//
// Extensible theming with persistence.
// Add new themes by adding a case to AppTheme
// and defining its palette.
// ─────────────────────────────────────────────

// MARK: - Theme Palette

struct ThemePalette {
    let background:       Color
    let cardBackground:   Color
    let accent:           Color
    let secondaryAccent:  Color
    let textPrimary:      Color
    let textSecondary:    Color
    let positive:         Color
    let negative:         Color
    let colorScheme:      ColorScheme?
}

// MARK: - AppTheme Enum

enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light
    case rainbow
    case pastel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark:    "Dark"
        case .light:   "Light"
        case .rainbow: "Rainbow"
        case .pastel:  "Pastel"
        }
    }

    var iconName: String {
        switch self {
        case .dark:    "moon.fill"
        case .light:   "sun.max.fill"
        case .rainbow: "rainbow"
        case .pastel:  "paintpalette.fill"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .dark:
            ThemePalette(
                background:      Color(red: 0.05, green: 0.08, blue: 0.15),
                cardBackground:  Color(red: 0.10, green: 0.13, blue: 0.20),
                accent:          Color(red: 0.18, green: 0.80, blue: 0.44),
                secondaryAccent: Color(red: 0.20, green: 0.60, blue: 0.90),
                textPrimary:     .white,
                textSecondary:   .gray,
                positive:        Color(red: 0.18, green: 0.80, blue: 0.44),
                negative:        Color(red: 0.90, green: 0.25, blue: 0.25),
                colorScheme:     .dark
            )
        case .light:
            ThemePalette(
                background:      Color(red: 0.96, green: 0.96, blue: 0.97),
                cardBackground:  .white,
                accent:          Color(red: 0.00, green: 0.48, blue: 1.00),
                secondaryAccent: Color(red: 0.35, green: 0.35, blue: 0.80),
                textPrimary:     .black,
                textSecondary:   .gray,
                positive:        Color(red: 0.13, green: 0.59, blue: 0.33),
                negative:        Color(red: 0.80, green: 0.15, blue: 0.15),
                colorScheme:     .light
            )
        case .rainbow:
            ThemePalette(
                background:      Color(red: 0.18, green: 0.05, blue: 0.28),
                cardBackground:  Color(red: 0.25, green: 0.08, blue: 0.38),
                accent:          Color(red: 1.00, green: 0.35, blue: 0.55),
                secondaryAccent: Color(red: 0.20, green: 0.80, blue: 1.00),
                textPrimary:     Color(red: 1.00, green: 0.95, blue: 0.55),
                textSecondary:   Color(red: 0.70, green: 0.55, blue: 1.00),
                positive:        Color(red: 0.10, green: 1.00, blue: 0.65),
                negative:        Color(red: 1.00, green: 0.30, blue: 0.30),
                colorScheme:     .dark
            )
        case .pastel:
            ThemePalette(
                background:      Color(red: 0.96, green: 0.94, blue: 0.98),
                cardBackground:  Color(red: 1.00, green: 0.98, blue: 1.00),
                accent:          Color(red: 0.68, green: 0.55, blue: 0.85),
                secondaryAccent: Color(red: 0.55, green: 0.75, blue: 0.90),
                textPrimary:     Color(red: 0.25, green: 0.22, blue: 0.30),
                textSecondary:   Color(red: 0.55, green: 0.50, blue: 0.60),
                positive:        Color(red: 0.55, green: 0.80, blue: 0.60),
                negative:        Color(red: 0.90, green: 0.55, blue: 0.60),
                colorScheme:     .light
            )
        }
    }
}

// MARK: - ThemeManager

@MainActor
@Observable
class ThemeManager {
    static let shared = ThemeManager()

    var currentTheme: AppTheme {
        didSet {
            // Persist selection
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "selectedTheme")
        }
    }

    var palette: ThemePalette { currentTheme.palette }

    var preferredColorScheme: ColorScheme? { palette.colorScheme }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "selectedTheme") ?? ""
        self.currentTheme = AppTheme(rawValue: saved) ?? .dark
    }
}
