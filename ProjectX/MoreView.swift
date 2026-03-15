import SwiftUI

// ─────────────────────────────────────────────
// ThemesView
//
// Theme selection tab.
// ─────────────────────────────────────────────

struct ThemesView: View {
    @Environment(ThemeManager.self) var themeManager

    var body: some View {
        @Bindable var tm = themeManager

        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $tm.currentTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.displayName, systemImage: theme.iconName)
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Themes")
        }
    }
}
