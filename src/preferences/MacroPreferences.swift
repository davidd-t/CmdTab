enum MenubarIconPreference: CaseIterable, MacroPreference {
    // Persisted indices and menubar-N.pdf assets share this order.
    case outlined
    case filled
    case colored

    var isTemplate: Bool { self != .colored }

    var localizedString: LocalizedString {
        switch self {
            // NSPopUpButton requires unique titles, including the image-only choices.
            case .outlined: return " "
            case .filled: return " "
            case .colored: return " "
        }
    }
}

enum GesturePreference: CaseIterable, MacroPreference {
    case disabled
    case threeFingerHorizontalSwipe
    case threeFingerVerticalSwipe
    case fourFingerHorizontalSwipe
    case fourFingerVerticalSwipe

    var localizedString: LocalizedString {
        switch self {
            case .disabled: return NSLocalizedString("Off", comment: "")
            case .threeFingerHorizontalSwipe: return NSLocalizedString("Three fingers, left or right", comment: "")
            case .threeFingerVerticalSwipe: return NSLocalizedString("Three fingers, up or down", comment: "")
            case .fourFingerHorizontalSwipe: return NSLocalizedString("Four fingers, left or right", comment: "")
            case .fourFingerVerticalSwipe: return NSLocalizedString("Four fingers, up or down", comment: "")
        }
    }

    func isHorizontal() -> Bool {
        return self == .threeFingerHorizontalSwipe || self == .fourFingerHorizontalSwipe
    }

    func isThreeFinger() -> Bool {
        return self == .threeFingerHorizontalSwipe || self == .threeFingerVerticalSwipe
    }
}

enum ShortcutStylePreference: CaseIterable, SfSymbolMacroPreference {
    case focusOnRelease
    case doNothingOnRelease
    case searchOnRelease

    var localizedString: LocalizedString {
        switch self {
            case .focusOnRelease: return NSLocalizedString("Switch to the selected window", comment: "")
            case .doNothingOnRelease: return NSLocalizedString("Keep the switcher open", comment: "")
            case .searchOnRelease: return NSLocalizedString("Start a search", comment: "")
        }
    }

    var symbol: Symbols {
        switch self {
            case .focusOnRelease: return .cursorarrowRays
            case .doNothingOnRelease: return .pauseRectangle
            case .searchOnRelease: return .magnifyingglass
        }
    }
}

enum ShowHowPreference: CaseIterable, MacroPreference {
    case show
    case hide
    case showAtTheEnd

    var localizedString: LocalizedString {
        switch self {
            case .show: return NSLocalizedString("Show", comment: "")
            case .showAtTheEnd: return NSLocalizedString("Show last", comment: "")
            case .hide: return NSLocalizedString("Hide", comment: "")
        }
    }
}

enum WindowOrderPreference: CaseIterable, MacroPreference {
    case recentlyFocused
    case recentlyCreated
    case alphabetical
    case space

    var localizedString: LocalizedString {
        switch self {
            case .recentlyFocused: return NSLocalizedString("Recently used first", comment: "")
            case .recentlyCreated: return NSLocalizedString("Recently opened first", comment: "")
            case .alphabetical: return NSLocalizedString("By name", comment: "")
            case .space: return NSLocalizedString("By Space", comment: "")
        }
    }
}

enum AppsToShowPreference: CaseIterable, MacroPreference {
    case all
    case active
    case nonActive
    case underCursor
    case appUnderCursor

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All apps", comment: "")
            case .active: return NSLocalizedString("Current app", comment: "")
            case .nonActive: return NSLocalizedString("Other apps", comment: "")
            case .underCursor: return NSLocalizedString("Windows under the pointer", comment: "")
            case .appUnderCursor: return NSLocalizedString("App under the pointer", comment: "")
        }
    }
}

enum SpacesToShowPreference: CaseIterable, MacroPreference {
    case all
    case visible
    case nonVisible

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All Spaces", comment: "")
            case .visible: return NSLocalizedString("Current Spaces", comment: "")
            case .nonVisible: return NSLocalizedString("Other Spaces", comment: "")
        }
    }
}

enum ScreensToShowPreference: CaseIterable, MacroPreference {
    case all
    case showingCmdTab

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All displays", comment: "")
            case .showingCmdTab: return NSLocalizedString("The display showing CmdTab", comment: "")
        }
    }
}

enum ShowOnScreenPreference: CaseIterable, MacroPreference {
    case active
    case includingMouse
    case includingMenubar

    var localizedString: LocalizedString {
        switch self {
            case .active: return NSLocalizedString("The active display", comment: "")
            case .includingMouse: return NSLocalizedString("The display with the pointer", comment: "")
            case .includingMenubar: return NSLocalizedString("The display with the menu bar", comment: "")
        }
    }
}

enum TitleTruncationPreference: CaseIterable, MacroPreference {
    case start
    case middle
    case end

    var localizedString: LocalizedString {
        switch self {
            case .start: return NSLocalizedString("At the start", comment: "")
            case .middle: return NSLocalizedString("In the middle", comment: "")
            case .end: return NSLocalizedString("At the end", comment: "")
        }
    }
}

enum GroupAppsPreference: CaseIterable, MacroPreference {
    case mainWindow
    case allWindows

    var localizedString: LocalizedString {
        switch self {
            case .mainWindow: return NSLocalizedString("One per app", comment: "")
            case .allWindows: return NSLocalizedString("Every window", comment: "")
        }
    }
}

/// Mirrors `showTabsAsWindows` as a 2-case enum so the per-shortcut UI renders a dropdown rather
/// than a switch. Persistence is by index (`"0"` / `"1"`), so `singleWindow` MUST stay at index 0
/// and `separateWindows` at index 1 — the migration that converts the old `"true"`/`"false"` Bool
/// strings relies on that mapping (true → separateWindows = "1", false → singleWindow = "0").
enum GroupTabsPreference: CaseIterable, MacroPreference {
    case singleWindow
    case separateWindows

    var localizedString: LocalizedString {
        switch self {
            case .singleWindow: return NSLocalizedString("One for all tabs", comment: "")
            case .separateWindows: return NSLocalizedString("One for each tab", comment: "")
        }
    }
}

enum CursorFollowFocus: CaseIterable, MacroPreference {
    case never
    case always
    case differentScreen

    var localizedString: LocalizedString {
        switch self {
            case .never: return NSLocalizedString("Never", comment: "")
            case .always: return NSLocalizedString("Always", comment: "")
            case .differentScreen: return NSLocalizedString("Only to another display", comment: "")
        }
    }
}

enum ShowTitlesPreference: CaseIterable, MacroPreference {
    case windowTitle
    case appName
    case appNameAndWindowTitle

    var localizedString: LocalizedString {
        switch self {
            case .windowTitle: return NSLocalizedString("Window title", comment: "")
            case .appName: return NSLocalizedString("App name", comment: "")
            case .appNameAndWindowTitle: return NSLocalizedString("App name – window title", comment: "")
        }
    }

    var image: WidthHeightImage {
        switch self {
            case .windowTitle: return WidthHeightImage(name: "show_running_windows")
            case .appName: return WidthHeightImage(name: "show_running_applications")
            case .appNameAndWindowTitle: return WidthHeightImage(name: "show_running_applications_windows")
        }
    }
}

enum AppearanceStylePreference: CaseIterable, ImageMacroPreference {
    case thumbnails
    case appIcons
    case titles

    var localizedString: LocalizedString {
        switch self {
            case .thumbnails: return NSLocalizedString("Thumbnails", comment: "")
            case .appIcons: return NSLocalizedString("App icons", comment: "")
            case .titles: return NSLocalizedString("Titles", comment: "")
        }
    }

    var image: WidthHeightImage {
        let width = CGFloat(150)
        let height = width / 1.6
        switch self {
            case .thumbnails: return WidthHeightImage(width: width, height: height, name: "thumbnails")
            case .appIcons: return WidthHeightImage(width: width, height: height, name: "app_icons")
            case .titles: return WidthHeightImage(width: width, height: height, name: "titles")
        }
    }
}

enum AppearanceSizePreference: CaseIterable, SfSymbolMacroPreference {
    case small
    case medium
    case large
    case auto

    var localizedString: LocalizedString {
        switch self {
            case .small: return NSLocalizedString("Small", comment: "")
            case .medium: return NSLocalizedString("Medium", comment: "")
            case .large: return NSLocalizedString("Large", comment: "")
            case .auto: return NSLocalizedString("Auto", comment: "")
        }
    }

    var symbol: Symbols {
        switch self {
            case .small: return .moonphaseWaningGibbousInverse
            case .medium: return .moonphaseLastQuarterInverse
            case .large: return .moonphaseWaningCrescentInverse
            case .auto: return .sparkles
        }
    }
}

enum AppearanceThemePreference: CaseIterable, SfSymbolMacroPreference {
    case light
    case dark
    case system

    var localizedString: LocalizedString {
        switch self {
            case .light: return NSLocalizedString("Light", comment: "")
            case .dark: return NSLocalizedString("Dark", comment: "")
            case .system: return NSLocalizedString("Match system", comment: "")
        }
    }

    var symbol: Symbols {
        switch self {
            case .light: return .sunMax
            case .dark: return .moonFill
            case .system: return .laptopcomputer
        }
    }
}

enum ExceptionHidePreference: String/* required for jsonEncode */, CaseIterable, MacroPreference, Codable {
    case none = "0"
    case always = "1"
    case whenNoOpenWindow = "2"
    case windowTitleContains = "3"

    var localizedString: LocalizedString {
        switch self {
            case .none: return ""
            case .always: return NSLocalizedString("Always", comment: "")
            case .whenNoOpenWindow: return NSLocalizedString("When it has no open window", comment: "")
            case .windowTitleContains: return NSLocalizedString("When the window title contains", comment: "")
        }
    }
}

enum ExceptionIgnorePreference: String/* required for jsonEncode */, CaseIterable, MacroPreference, Codable {
    case none = "0"
    case always = "1"
    case whenFullscreen = "2"

    var localizedString: LocalizedString {
        switch self {
            case .none: return ""
            case .always: return NSLocalizedString("Always", comment: "")
            case .whenFullscreen: return NSLocalizedString("When in full screen", comment: "")
        }
    }
}

// MacroPreference are collection of values derived from a single key
// we don't want to store every value in UserDefaults as the user could change them and contradict the macro
protocol MacroPreference {
    var localizedString: LocalizedString { get }
}

protocol SfSymbolMacroPreference: MacroPreference {
    var symbol: Symbols { get }
}

protocol ImageMacroPreference: MacroPreference {
    var image: WidthHeightImage { get }
}

struct WidthHeightImage {
    var width: CGFloat
    var height: CGFloat
    var name: String

    init(width: CGFloat = 80, height: CGFloat = 50, name: String) {
        self.width = width
        self.height = height
        self.name = name
    }
}

typealias LocalizedString = String
