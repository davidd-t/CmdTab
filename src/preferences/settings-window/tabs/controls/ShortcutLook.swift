import Foundation

enum ShortcutLook {
    static let overrides: [(override: String, global: String)] = [
        ("appearanceStyleOverride", "appearanceStyle"),
        ("appearanceSizeOverride", "appearanceSize"),
        ("appearanceThemeOverride", "appearanceTheme"),
        ("shortcutStyleOverride", "shortcutStyle"),
        ("previewFocusedWindowOverride", "previewFocusedWindow"),
    ]

    /// Same rule as `Preferences.indexToName`.
    static func key(_ base: String, _ index: Int) -> String {
        index == 0 ? base : base + String(index + 1)
    }

    /// `stored` is the persistent domain, so registered defaults don't count.
    static func followsAppearance(stored: [String: Any], index: Int) -> Bool {
        !overrides.contains { stored[key($0.override, index)] != nil }
    }

    static func writesWhenTurnedOff(index: Int, effective: (String) -> String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: overrides.map { (key($0.override, index), effective($0.global)) })
    }

    static func keysToRemoveWhenTurnedOn(index: Int) -> [String] {
        overrides.map { key($0.override, index) }
    }
}
