import Cocoa

class PreferencesMigrations {
    static var defaults = UserDefaults.standard

    /// An empty string stored as a hold shortcut cannot be parsed back into one; drop it so the default applies.
    static func removeCorruptedPreferences() {
        ["holdShortcut", "holdShortcut2", "holdShortcut3", "holdShortcut4", "holdShortcut5"].forEach {
            if let s = Self.defaults.string(forKey: $0), s == "" {
                Self.defaults.removeObject(forKey: $0)
            }
        }
    }

    private static let freshInstallKey = "isFreshInstall"

    /// True when this install started with no preferences at all. Persisted on the first launch, the only
    /// one that can still observe a nil `preferencesVersion`, so an unfinished onboarding can resume later.
    static var isFreshInstall: Bool { Self.defaults.bool(forKey: freshInstallKey) }

    private static func markFreshInstallIfUnknown(_ value: Bool) {
        guard Self.defaults.object(forKey: freshInstallKey) == nil else { return }
        Self.defaults.set(value, forKey: freshInstallKey)
    }

    /// Records which version wrote the preferences. A future change to how a preference is stored can compare
    /// against it to convert older values.
    static func migratePreferences() {
        let preferencesKey = "preferencesVersion"
        markFreshInstallIfUnknown(Self.defaults.string(forKey: preferencesKey) == nil)
        Self.defaults.set(App.version, forKey: preferencesKey)
    }
}
