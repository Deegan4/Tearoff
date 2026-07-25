import SwiftUI

/// The user's chosen app appearance. Persisted via `@AppStorage("appearanceMode")`
/// and applied at the app root with `.preferredColorScheme`. `system` follows the
/// device setting; the other two override it.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// The scheme to force, or `nil` to follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The shared persistence key, so the app root and Settings read the same value.
extension AppearanceMode {
    static let storageKey = "appearanceMode"
}
