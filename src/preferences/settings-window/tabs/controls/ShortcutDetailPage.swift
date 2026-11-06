import Cocoa

/// A shortcut's own page (or the trackpad gesture's): its keys, which windows it shows, their
/// order, its look, and Remove Shortcut…. Built each time it opens.
enum ShortcutDetailPage {
    static let labelShortcut = NSLocalizedString("Shortcut", comment: "")
    static let labelGesture = NSLocalizedString("Swipe", comment: "The trackpad gesture that opens the switcher")
    static let labelRemove = NSLocalizedString("Remove Shortcut…", comment: "")
    static let labelOpenTrackpadSettings = NSLocalizedString("Open Trackpad Settings…", comment: "")
    static let gestureHint = NSLocalizedString("You may need to disable some conflicting system gestures", comment: "")

    /// Labels on these pages, for search from the Shortcuts section.
    static var searchableStrings: [String] {
        [labelShortcut, TriggerBinding.holdLabelText, TriggerBinding.thenPressText, labelGesture,
         labelRemove, labelOpenTrackpadSettings, gestureHint]
            + GesturePreference.allCases.map { $0.localizedString }
            + FilteringPane.searchableStrings + OrderingPane.searchableStrings + AppearancePane.searchableStrings
    }

    static func make(index: Int, width: CGFloat) -> (title: String, view: NSView) {
        let isGesture = index == Preferences.gestureIndex
        let title = Self.title(index)
        let page = PageView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 22
        page.translatesAutoresizingMaskIntoConstraints = false

        let header = isGesture
            ? SettingsWindow.makePageHeader(tile: trackpadTile(size: SettingsWindow.pageHeaderTileSize), keys: nil, title: title, description: gestureDescription())
            : SettingsWindow.makePageHeader(tile: nil, keys: ShortcutsTab.keys(index).map { ShortcutsTab.keycapGlyphs($0) } ?? holdGlyphs(index),
                                            title: title, description: shortcutDescription(index))
        page.addArrangedSubview(header)
        page.setCustomSpacing(20, after: header)
        header.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        if isGesture {
            page.addArrangedSubview(makeGestureGroup(width))
        } else {
            let trigger = TriggerBinding()
            trigger.bind(toShortcut: index)
            page.retained.append(trigger)
            let group = TableGroupView(heading: nil, width: width)
            group.addRow(leftText: labelShortcut, rightViews: [trigger.view])
            page.addArrangedSubview(group)
        }

        let filtering = FilteringPane(width: width)
        filtering.bind(toShortcut: index)
        let ordering = OrderingPane(width: width)
        ordering.bind(toShortcut: index)
        let look = AppearancePane(width: width)
        look.bind(toShortcut: index)
        page.retained += [filtering, ordering, look]
        [filtering.view, ordering.view, look.view].forEach { page.addArrangedSubview($0) }

        if !isGesture && Preferences.shortcutCount > Preferences.minShortcutCount {
            let remove = NSButton(title: labelRemove, target: nil, action: nil)
            remove.bezelStyle = .rounded
            remove.hasDestructiveAction = true
            remove.onAction = { _ in confirmRemove(index) }
            page.addArrangedSubview(remove)
            page.setCustomSpacing(10, after: look.view)
        }
        return (title, page)
    }

    // MARK: - Header

    /// The page's title: the shortcut's automatic name, or the gesture's.
    static func title(_ index: Int) -> String {
        index == Preferences.gestureIndex ? ShortcutNaming.gestureName : name(index)
    }

    private static func name(_ index: Int) -> String {
        let names = ShortcutNaming.names(ShortcutsTab.inputsForNaming())
        return index < names.count ? names[index] : labelShortcut
    }

    private static func holdGlyphs(_ index: Int) -> [String] {
        let hold = Preferences.shortcut(Preferences.indexToName("holdShortcut", index))?.keyEquivalent ?? ""
        return hold.isEmpty ? [] : ShortcutsTab.keycapGlyphs(hold)
    }

    private static func shortcutDescription(_ index: Int) -> String {
        let hold = Preferences.shortcut(Preferences.indexToName("holdShortcut", index))?.keyEquivalent ?? ""
        let next = Preferences.shortcut(Preferences.indexToName("nextWindowShortcut", index))?.keyEquivalent ?? ""
        if next.isEmpty {
            return NSLocalizedString("Choose the keys that open the switcher.", comment: "")
        }
        if hold.isEmpty {
            return String(format: NSLocalizedString("Press %@ to open the switcher.", comment: ""), next)
        }
        return String(format: NSLocalizedString("Hold %@ and press %@ to open the switcher.", comment: ""), hold, next)
    }

    private static func gestureDescription() -> String {
        let gesture = Preferences.nextWindowGesture
        if gesture == .disabled {
            return NSLocalizedString("Choose a trackpad swipe that opens the switcher.", comment: "")
        }
        return String(format: NSLocalizedString("A %@ opens the switcher.", comment: "e.g. A 3-finger Horizontal Swipe opens the switcher."),
                      gesture.localizedString.lowercased())
    }

    /// The trackpad symbol on a tile in the Shortcuts section's color.
    private static func trackpadTile(size: CGFloat) -> NSImage? {
        let symbol = NSImage(systemSymbolName: "rectangle.and.hand.point.up.left", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: nil)
        return SettingsWindow.sectionTile("shortcuts", size: size, symbol: symbol)
    }

    // MARK: - Gesture

    private static func makeGestureGroup(_ width: CGFloat) -> NSView {
        let group = TableGroupView(heading: nil, width: width)
        let dropdown = LabelAndControl.makeDropdown("nextWindowGesture", GesturePreference.allCases)
        dropdown.setAccessibilityLabel(labelGesture)
        group.addRow(leftText: labelGesture, rightViews: [dropdown])
        let open = NSButton(title: labelOpenTrackpadSettings, target: nil, action: nil)
        open.bezelStyle = .rounded
        open.onAction = { _ in
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
        }
        group.addRow(leftText: gestureHint, rightViews: [open])
        return group
    }

    // MARK: - Remove

    private static func confirmRemove(_ index: Int) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: NSLocalizedString("Remove “%@”?", comment: "Remove “All windows”?"), name(index))
        alert.informativeText = NSLocalizedString("Its keys stop opening the switcher, and its settings are deleted.", comment: "")
        let removeButton = alert.addButton(withTitle: NSLocalizedString("Remove", comment: ""))
        removeButton.hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        alert.present(attachedTo: SettingsWindow.shared) {
            guard $0 == .alertFirstButtonReturn else { return }
            remove(index)
        }
    }

    private static func remove(_ index: Int) {
        ShortcutsTab.removeShortcut(at: index)
        AppearanceTab.refreshLookNote()
        // Later shortcuts move up one slot, so their pages (and this one) leave the history.
        SettingsWindow.shared?.removePages(where: {
            if case .shortcut(let j) = $0 { return j >= index && j != Preferences.gestureIndex }
            return false
        }, fallback: .section("shortcuts"))
    }
}

/// Keeps the page's bindings alive while the page is on screen.
private final class PageView: NSStackView {
    var retained = [AnyObject]()
}
