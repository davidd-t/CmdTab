import Cocoa
import UniformTypeIdentifiers

class GeneralTab {
    /// The three menu bar icon choices, as picture buttons. `Menubar` enables and disables it.
    static var menubarIconDropdown: NSSegmentedControl?
    static var menuIconShownToggle: Switch?

    static func initTab() -> NSView {
        let width = SettingsWindow.contentWidth
        func labeled<T: NSView>(_ view: T, _ label: String) -> T {
            view.setAccessibilityLabel(label)
            return view
        }

        let startup = TableGroupView(heading: nil, width: width)
        let login = NSLocalizedString("Open CmdTab at login", comment: "")
        startup.addRow(leftText: login, rightViews: [labeled(LabelAndControl.makeSwitch("startAtLogin"), login)])

        let menuBar = TableGroupView(heading: NSLocalizedString("Menu bar", comment: ""), width: width)
        let show = NSLocalizedString("Show in menu bar", comment: "")
        let shown = LabelAndControl.makeSwitch("menubarIconShown", extraAction: { _ in
            menubarIconDropdown?.isEnabled = Preferences.menubarIconShown
        })
        menuIconShownToggle = shown
        menuBar.addRow(leftText: show, rightViews: [labeled(shown, show)])
        let iconLabel = NSLocalizedString("Icon", comment: "")
        let icons = LabelAndControl.makeSegmentedControl("menubarIcon", MenubarIconPreference.allCases)
        for (i, preference) in MenubarIconPreference.allCases.enumerated() {
            let image = NSImage.initCopy("menubar-\(i)")
            image.isTemplate = preference.isTemplate
            image.size = NSSize(width: 20, height: 20)
            icons.setImage(image, forSegment: i)
            icons.setLabel("", forSegment: i)
            icons.setWidth(44, forSegment: i)
        }
        icons.segmentStyle = .rounded
        icons.isEnabled = Preferences.menubarIconShown
        menubarIconDropdown = icons
        menuBar.addRow(leftText: iconLabel, rightViews: [labeled(icons, iconLabel)])

        let previews = TableGroupView(heading: NSLocalizedString("Window previews", comment: ""), width: width)
        let capture = NSLocalizedString("Keep previews up to date in the background", comment: "")
        previews.addRow(leftText: capture,
                        rightViews: [labeled(LabelAndControl.makeSwitch("captureWindowsInBackground"), capture)],
                        subText: NSLocalizedString("Turn off to avoid the purple screen-recording dot and flicker in DRM video. Previews will be less fresh.", comment: ""))

        let file = TableGroupView(heading: NSLocalizedString("Settings file", comment: ""), width: width)
        let exportButton = NSButton(title: NSLocalizedString("Export…", comment: ""), target: nil, action: nil)
        exportButton.onAction = { _ in exportSettings() }
        let importButton = NSButton(title: NSLocalizedString("Import…", comment: ""), target: nil, action: nil)
        importButton.onAction = { _ in importSettings() }
        file.addRow(leftText: NSLocalizedString("Save your settings to a file, or load them on another Mac.", comment: ""),
                    rightViews: [exportButton, importButton])
        let resetButton = NSButton(title: NSLocalizedString("Reset…", comment: ""), target: nil, action: nil)
        resetButton.hasDestructiveAction = true
        resetButton.onAction = { _ in resetPreferences() }
        let reset = NSLocalizedString("Reset all settings", comment: "")
        file.addRow(leftText: reset, rightViews: [labeled(resetButton, reset)],
                    subText: NSLocalizedString("CmdTab restarts with its defaults. You can't undo this.", comment: ""))

        let view = NSStackView(views: [startup, menuBar, previews, file])
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 22
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    static func cleanup() {
        menubarIconDropdown = nil
        menuIconShownToggle = nil
    }

    static func refreshControlsFromPreferences() {
        let selected = CachedUserDefaults.intFromMacroPref("menubarIcon", MenubarIconPreference.allCases)
        if selected >= 0 { menubarIconDropdown?.selectedSegment = selected }
        menubarIconDropdown?.isEnabled = Preferences.menubarIconShown
    }

    @objc static func resetPreferences() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = ""
        alert.informativeText = NSLocalizedString("You can’t undo this action.", comment: "")
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        let resetButton = alert.addButton(withTitle: NSLocalizedString("Reset settings and restart", comment: ""))
        resetButton.hasDestructiveAction = true
        alert.present(attachedTo: SettingsWindow.shared) {
            guard $0 == .alertSecondButtonReturn else { return }
            Preferences.resetAll()
            App.restart()
        }
    }

    private static func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(App.bundleIdentifier).plist"
        panel.allowedContentTypes = [.propertyList]
        presentPanel(panel) { NSDictionary(dictionary: Preferences.all).write(to: $0, atomically: true) }
    }

    private static func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        presentPanel(panel) { importSettings(from: $0) }
    }

    private static func importSettings(from url: URL) {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to import settings", comment: "")
            alert.present(attachedTo: SettingsWindow.shared) { _ in }
            return
        }
        let filtered = dict.filter { Preferences.ownedKeys.contains($0.key) }
        UserDefaults.standard.setPersistentDomain(filtered, forName: App.bundleIdentifier)
        CachedUserDefaults.cache.withLock { $0.removeAll() }
        Preferences.invalidateAllCache()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Settings imported", comment: "")
        alert.informativeText = NSLocalizedString("The application needs to restart to apply the imported settings.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Restart Now", comment: ""))
        let laterButton = alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
        laterButton.keyEquivalent = "\u{1b}" // Escape
        alert.present(attachedTo: SettingsWindow.shared) {
            if $0 == .alertFirstButtonReturn { App.restart() }
        }
    }

    /// Attached to Settings when it is on screen, like this tab's alerts. The choice is handled on the next turn,
    /// once the panel has left, so an alert that follows can take its place as the sheet.
    private static func presentPanel(_ panel: NSSavePanel, _ onChoice: @escaping (URL) -> Void) {
        let handle = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { onChoice(url) }
        }
        guard let settings = SettingsWindow.shared, settings.isVisible else { return handle(panel.runModal()) }
        panel.beginSheetModal(for: settings, completionHandler: handle)
    }
}
