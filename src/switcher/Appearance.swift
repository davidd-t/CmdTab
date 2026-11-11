import Cocoa

class Appearance {
    // size
    static var resolvedSize = AppearanceSizePreference.medium
    static var hideThumbnails = Bool(false)
    static var windowPadding = CGFloat(1000)
    static var windowCornerRadius = CGFloat(1000)
    static var cellCornerRadius = CGFloat(1000)
    static var edgeInsetsSize = CGFloat(1000)
    static var maxWidthOnScreen = CGFloat(1000)
    static var rowsCount = CGFloat(1000)
    static var iconSize = CGFloat(1000)
    static var fontHeight = CGFloat(3)
    static var font = NSFont.systemFont(ofSize: fontHeight)
    static var windowMinWidthInRow = CGFloat(1000)
    static var windowMaxWidthInRow = CGFloat(1000)

    // size: constants
    static let maxHeightOnScreen = CGFloat(0.8)
    static let interCellPadding = CGFloat(6)
    static let intraCellPadding = CGFloat(5)
    static let appIconLabelSpacing = CGFloat(2)

    // theme
    static var fontColor = NSColor.red
    static var imagesShadowColor = NSColor.red // for icon, thumbnail and windowless images
    static var material = LegacyMaterial.ultraDark
    static var highlightBorderWidth = CGFloat(2)
    /// Corner radius of the selection ring; follows what the ring wraps (see `TileView.highlightFrame`).
    static var highlightCornerRadius = CGFloat(12)

    // theme: constants
    static var enablePanelShadow = true
    // Selection is a thin accent ring with no tint; in the Thumbnails style it wraps the thumbnail
    // only, with a small gap, so the window itself reads as the selected thing.
    static let thumbnailCornerRadius = CGFloat(6)
    static let highlightRingGap = CGFloat(2)
    /// Titles and status icons of tiles that are neither selected nor hovered are dimmed to this.
    static let unfocusedTitleOpacity = CGFloat(0.55)
    private static var neutralInk: NSColor { currentTheme == .dark ? .white : .black }
    static var highlightFocusedBackgroundColor: NSColor { get { NSColor.clear } }
    static var highlightHoveredBackgroundColor: NSColor { get { NSColor.clear } }
    static var highlightFocusedBorderColor: NSColor { get { NSColor.controlAccentColor } }
    static var highlightHoveredBorderColor: NSColor { get { neutralInk.withAlphaComponent(0.35) } }
    /// Hairline around each thumbnail, so dark windows keep an edge against a dark panel.
    static var thumbnailBorderColor: NSColor { get { neutralInk.withAlphaComponent(0.14) } }
    /// Hairline around the frosted panel (Liquid Glass draws its own rim).
    static var panelBorderColor: NSColor { get { neutralInk.withAlphaComponent(0.12) } }
    static var searchMatchHighlightColor: NSColor { get { NSColor.systemYellow.withAlphaComponent(0.5) } }
    static var searchMatchForegroundColor: NSColor { get { NSColor(calibratedWhite: 0.12, alpha: 1) } }

    private static var currentStyle: AppearanceStylePreference { Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) }
    private static var currentSize: AppearanceSizePreference { Preferences.effectiveAppearanceSize(SwitcherSession.activeShortcutIndex) }
    static var currentTheme: AppearanceThemePreference {
        let theme = Preferences.effectiveAppearanceTheme(SwitcherSession.activeShortcutIndex)
        return theme == .system ? NSAppearance.currentDrawing().getThemeName() : theme
    }

    static func update() {
        updateSize()
        updateTheme()
    }

    private static func updateSize() {
        let isHorizontalScreen = NSScreen.preferred.isHorizontal()
        maxWidthOnScreen = AppearanceTestable.comfortableWidth(NSScreen.preferred.physicalSize().map { $0.width })
        let sizeToApply: AppearanceSizePreference = currentSize == .auto ? .large : currentSize
        resolvedSize = sizeToApply
        applyConcreteSize(sizeToApply, isHorizontalScreen)
        updateFont()
    }

    static func applySize(_ size: AppearanceSizePreference) {
        let isHorizontalScreen = NSScreen.preferred.isHorizontal()
        resolvedSize = size
        applyConcreteSize(size, isHorizontalScreen)
        updateFont()
    }

    private static func applyConcreteSize(_ size: AppearanceSizePreference, _ isHorizontalScreen: Bool) {
        if currentStyle == .appIcons {
            appIconsSize(size)
        } else if currentStyle == .titles {
            titlesSize(size)
        } else {
            thumbnailsSize(isHorizontalScreen, size)
        }
        // Concentric corners: panel > tile > thumbnail (`thumbnailCornerRadius`).
        windowCornerRadius = 20
        cellCornerRadius = 12
    }

    private static func updateTheme() {
        highlightBorderWidth = 2
        highlightCornerRadius = currentStyle == .thumbnails
            ? thumbnailCornerRadius + highlightRingGap + highlightBorderWidth
            : cellCornerRadius
        if currentTheme == .dark {
            darkTheme()
        } else {
            lightTheme()
        }
        // for Liquid Glass, we don't want a shadow around the panel
        if #available(macOS 26.0, *), currentStyle == .appIcons && LiquidGlass.canUsePrivateLook {
            enablePanelShadow = false
        } else {
            enablePanelShadow = true
        }
    }

    private static func thumbnailsSize(_ isHorizontalScreen: Bool, _ size: AppearanceSizePreference) {
        hideThumbnails = false
        // Tiles already carry `edgeInsetsSize` of their own, so the panel adds only a slim margin.
        windowPadding = 10
        edgeInsetsSize = 12
        switch size {
            case .small:
                rowsCount = isHorizontalScreen ? 5 : 8
                iconSize = 16
                fontHeight = 13
            case .medium:
                rowsCount = isHorizontalScreen ? 4 : 7
                iconSize = 26
                fontHeight = 14
            case .large, .auto:
                rowsCount = isHorizontalScreen ? 3 : 6
                iconSize = 28
                fontHeight = 16
        }
        let tilesPanelRatio = (NSScreen.preferred.frame.width * maxWidthOnScreen) / (NSScreen.preferred.frame.height * maxHeightOnScreen)
        (windowMinWidthInRow, windowMaxWidthInRow) = AppearanceTestable.goodValuesForThumbnailsWidthMinMax(tilesPanelRatio, rowsCount)
    }

    private static func appIconsSize(_ size: AppearanceSizePreference) {
        hideThumbnails = true
        windowPadding = 25
        windowCornerRadius = 23
        cellCornerRadius = 10
        edgeInsetsSize = 5
        if #available(macOS 26.0, *) {
            edgeInsetsSize = 6
        }
        windowMinWidthInRow = 0.04
        windowMaxWidthInRow = 0.3
        rowsCount = 1
        switch size {
            case .small:
                iconSize = 70
                fontHeight = 13
                if #available(macOS 26.0, *) {
                    windowCornerRadius = 50
                    cellCornerRadius = 24
                }
            case .medium:
                iconSize = 110
                fontHeight = 14
                if #available(macOS 26.0, *) {
                    windowCornerRadius = 55
                    cellCornerRadius = 35
                }
            case .large, .auto:
                windowPadding = 28
                iconSize = 150
                fontHeight = 16
                if #available(macOS 26.0, *) {
                    windowCornerRadius = 75
                    cellCornerRadius = 45
                }
        }
    }

    private static func titlesSize(_ size: AppearanceSizePreference) {
        hideThumbnails = true
        windowPadding = 18
        windowCornerRadius = 23
        cellCornerRadius = 10
        edgeInsetsSize = 7
        windowMinWidthInRow = 0.6
        windowMaxWidthInRow = 0.9
        rowsCount = 1
        switch size {
            case .small:
                iconSize = 18
                fontHeight = 13
            case .medium:
                iconSize = 24
                fontHeight = 14
            case .large, .auto:
                iconSize = 30
                fontHeight = 16
        }
    }

    private static func updateFont() {
        if #available(macOS 26.0, *) {
            font = NSFont.systemFont(ofSize: fontHeight, weight: currentStyle == .appIcons ? .semibold : .medium)
        } else {
            font = NSFont.systemFont(ofSize: fontHeight)
        }
    }

    private static func lightTheme() {
        fontColor = .black.withAlphaComponent(0.8)
        imagesShadowColor = .gray.withAlphaComponent(0.8)
        material = LegacyMaterial.mediumLight
    }

    private static func darkTheme() {
        fontColor = .white.withAlphaComponent(0.85)
        imagesShadowColor = .gray.withAlphaComponent(0.8)
        material = LegacyMaterial.dark
    }
}

/// The only `NSVisualEffectView.Material` values that pin light or dark explicitly. Deprecated in
/// 10.14 in favour of semantic materials, which we can't use: those follow the view's
/// `NSAppearance`, whereas our theme comes from the user's own preference (see `updateTheme`).
/// Referenced by rawValue because naming the cases trips `SWIFT_TREAT_WARNINGS_AS_ERRORS`.
enum LegacyMaterial {
    static let dark = NSVisualEffectView.Material(rawValue: 2)!
    static let mediumLight = NSVisualEffectView.Material(rawValue: 8)!
    static let ultraDark = NSVisualEffectView.Material(rawValue: 9)!
}
