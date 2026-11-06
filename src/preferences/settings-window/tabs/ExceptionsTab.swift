import Cocoa
import UniformTypeIdentifiers

/// The Exceptions page: one row per exception (each opening its own page), the two Add buttons and
/// a hint. Each exception's page (`detailPage`) edits it with `ExceptionEditorView`.
class ExceptionsTab {
    private static var items: [ExceptionEntry] = []
    /// Resolved app names and icons, by bundle ID. Resolving can touch the disk, so it runs off-main.
    private static var resolvedApps = [String: AppDisplayInfo]()
    private static var resolving = Set<String>()

    /// Holds the exceptions list group; rebuilt by `refreshList` when a row's content changes.
    private static weak var listContainer: SeparatelyIndexedView?
    private static var shownListEntries = [ListEntry]()
    /// The rows' titles and subtitles, published to search by `registerListSearchContent`.
    private static var listTitleLabels = [LightLabel]()
    private static var listSubtitleLabels = [NSTextField]()

    private struct ListEntry: Equatable {
        let bundleId: String
        let name: String
        let summary: String
        let isResolved: Bool
    }

    static let labelHide = NSLocalizedString("Hide in the switcher", comment: "")
    static let labelIgnore = NSLocalizedString("Turn off CmdTab's shortcuts", comment: "")
    static let labelBundleId = NSLocalizedString("Bundle ID", comment: "")
    static let labelAddPattern = NSLocalizedString("Add a pattern", comment: "")
    static let hideOptionTitles = [
        NSLocalizedString("Never", comment: ""),
        NSLocalizedString("Always", comment: ""),
        NSLocalizedString("When it has no open window", comment: ""),
        NSLocalizedString("When the window title contains…", comment: ""),
    ]
    static let ignoreOptionTitles = [
        NSLocalizedString("Never", comment: ""),
        NSLocalizedString("Always", comment: ""),
        NSLocalizedString("When in full screen", comment: ""),
    ]
    private static let labelRemove = NSLocalizedString("Remove Exception…", comment: "")

    static func initTab() -> NSView {
        items = Preferences.exceptions
        let width = SettingsWindow.contentWidth
        let list = SeparatelyIndexedView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        listContainer = list
        shownListEntries = []
        list.widthAnchor.constraint(equalToConstant: width).isActive = true

        let addRunning = NSButton(title: NSLocalizedString("Add Running App…", comment: ""), target: self, action: #selector(addRunningAppClicked(_:)))
        let addFromDisk = NSButton(title: NSLocalizedString("Add App from Disk…", comment: ""), target: self, action: #selector(addFromDiskClicked))
        [addRunning, addFromDisk].forEach { $0.bezelStyle = .rounded }
        let buttons = NSStackView(views: [addRunning, addFromDisk])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let hint = NSTextField(wrappingLabelWithString: NSLocalizedString("Remote desktop and virtual machine apps are listed by default, so ⌘Tab reaches the computer inside them when they're fullscreen.", comment: ""))
        hint.font = TableGroupView.subtitleFont
        hint.textColor = .secondaryLabelColor
        hint.isSelectable = false
        hint.preferredMaxLayoutWidth = width - 2 * TableGroupView.rowHorizontalPadding
        let hintRow = NSStackView(views: [hint])
        hintRow.edgeInsets = NSEdgeInsets(top: 0, left: TableGroupView.rowHorizontalPadding, bottom: 0, right: TableGroupView.rowHorizontalPadding)

        // Settings on each exception's own page: found by search from this section.
        // They open the first exception's page, or this list when there is none.
        SettingsSearchIndex.registerDetailStrings([labelHide, labelIgnore, labelBundleId, labelAddPattern, labelRemove] + hideOptionTitles + ignoreOptionTitles) {
            guard let first = items.first else { return (.section("exceptions"), NSLocalizedString("Exceptions", comment: "")) }
            let info = resolvedApps[first.bundleIdentifier] ?? AppDisplayInfo.resolve(bundleId: first.bundleIdentifier)
            resolvedApps[first.bundleIdentifier] = info
            return (.exception(0), info.name)
        }

        let view = NSStackView(views: [list, buttons, hintRow])
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 10
        view.setCustomSpacing(12, after: buttons)
        view.translatesAutoresizingMaskIntoConstraints = false
        refreshList()
        return view
    }

    static func cleanup() {
        items.removeAll()
        listContainer = nil
        shownListEntries = []
        listTitleLabels = []
        listSubtitleLabels = []
    }

    #if DEBUG
    /// For the Debug-only page renderer: shows a Finder exception when there is none, in memory only.
    static func addRenderSampleIfEmpty() {
        guard items.isEmpty else { return }
        items = [ExceptionEntry(bundleIdentifier: "com.apple.finder", hide: .whenNoOpenWindow, ignore: .none)]
        refreshList()
    }
    #endif

    private static func savePreferences() {
        Preferences.set("exceptions", items)
    }

    // MARK: - List

    private static func appInfo(_ bundleId: String) -> AppDisplayInfo? {
        if let info = resolvedApps[bundleId] { return info }
        guard !resolving.contains(bundleId) else { return nil }
        resolving.insert(bundleId)
        DispatchQueue.global(qos: .userInitiated).async {
            let info = AppDisplayInfo.resolve(bundleId: bundleId)
            DispatchQueue.main.async {
                resolving.remove(bundleId)
                resolvedApps[bundleId] = info
                refreshList()
            }
        }
        return nil
    }

    private static func listEntries() -> [ListEntry] {
        items.map { entry in
            let info = appInfo(entry.bundleIdentifier)
            return ListEntry(bundleId: entry.bundleIdentifier, name: info?.name ?? entry.bundleIdentifier,
                             summary: ExceptionSummary.text(hide: entry.hide, ignore: entry.ignore), isResolved: info != nil)
        }
    }

    /// Rebuilds the exceptions list if an app's name, icon or summary changed.
    static func refreshList() {
        guard let list = listContainer else { return }
        let entries = listEntries()
        guard entries != shownListEntries else { return }
        shownListEntries = entries
        let update = {
            list.arrangedSubviews.forEach { $0.removeFromSuperview() }
            listTitleLabels = []
            listSubtitleLabels = []
            guard !entries.isEmpty else { return }
            // Not indexed here: `registerListSearchContent` publishes the rows.
            let group = SettingsSearchIndex.unindexed { makeListGroup(entries) }
            list.addArrangedSubview(group)
        }
        if let window = SettingsWindow.shared, list.window === window {
            window.preserveScrollPosition(during: update)
        } else {
            update()
        }
        SettingsWindow.shared?.refreshSectionSearchContent("exceptions")
    }

    private static func makeListGroup(_ entries: [ListEntry]) -> TableGroupView {
        let group = TableGroupView(heading: nil, width: SettingsWindow.contentWidth)
        for (index, entry) in entries.enumerated() {
            let icon = resolvedApps[entry.bundleId]?.icon ?? AppDisplayInfo.genericIcon
            let row = group.addNavigationRow(title: entry.name, subtitle: entry.summary, accessory: nil, icon: icon) {
                SettingsWindow.shared?.open(.exception(index))
            }
            listTitleLabels += (row.leftViews ?? []).compactMap { $0 as? LightLabel }
            if let subtitle = row.subtitleLabel { listSubtitleLabels.append(subtitle) }
        }
        return group
    }

    /// Publishes the list rows' titles and subtitles to search. Invoked by
    /// `SettingsWindow.refreshSectionSearchContent("exceptions")` inside a fresh `indexed { }` scope.
    static func registerListSearchContent() {
        listTitleLabels.forEach {
            SettingsSearchIndex.registerString($0.stringValue)
            SettingsSearchIndex.registerTarget(SettingsSearchHighlight.highlightTarget($0))
        }
        listSubtitleLabels.forEach {
            SettingsSearchIndex.registerString($0.stringValue)
            SettingsSearchIndex.registerTarget(SettingsSearchHighlight.highlightTarget($0))
        }
    }

    // MARK: - Adding

    @objc private static func addRunningAppClicked(_ sender: NSButton) {
        let menu = NSMenu()
        let apps = runningAppsForMenu()
        if apps.isEmpty {
            let item = NSMenuItem(title: NSLocalizedString("No other running apps", comment: ""), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        apps.forEach { menu.addItem(makeRunningAppItem($0.app, $0.bundleId)) }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private static func addFromDiskClicked() {
        let dialog = NSOpenPanel()
        dialog.allowsMultipleSelection = false
        dialog.allowedContentTypes = [.application]
        dialog.canChooseDirectories = false
        dialog.beginSheetModal(for: SettingsWindow.shared) {
            if $0 == .OK, let url = dialog.url, let bundleId = Bundle(url: url)?.bundleIdentifier {
                addException(bundleId)
            }
        }
    }

    private static func runningAppsForMenu() -> [(app: NSRunningApplication, bundleId: String)] {
        let existingIds = Set(items.map { $0.bundleIdentifier })
        var appsByBundleId = [String: NSRunningApplication]()
        runningAppCandidates().forEach {
            guard let bundleId = $0.bundleIdentifier, !existingIds.contains(bundleId), appsByBundleId[bundleId] == nil else { return }
            appsByBundleId[bundleId] = $0
        }
        return appsByBundleId.map { ($0.value, $0.key) }.sorted { appMenuTitle($0.app).localizedStandardCompare(appMenuTitle($1.app)) == .orderedAscending }
    }

    private static func runningAppCandidates() -> [NSRunningApplication] {
        Windows.list.map { $0.application.runningApplication } + NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    private static func makeRunningAppItem(_ app: NSRunningApplication, _ bundleId: String) -> NSMenuItem {
        let item = NSMenuItem(title: appMenuTitle(app), action: #selector(addRunningApp(_:)), keyEquivalent: "")
        if let path = app.bundleURL?.path {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        item.representedObject = bundleId
        item.target = self
        return item
    }

    private static func appMenuTitle(_ app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleIdentifier ?? ""
    }

    @objc private static func addRunningApp(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String else { return }
        addException(bundleId)
    }

    /// Adds an exception for `bundleId` (hidden always, as today) and opens its page. An app that
    /// already has one just opens its page.
    private static func addException(_ bundleId: String) {
        if let existing = items.firstIndex(where: { $0.bundleIdentifier == bundleId }) {
            SettingsWindow.shared?.open(.exception(existing))
            return
        }
        items.append(ExceptionEntry(bundleIdentifier: bundleId, hide: .always, ignore: .none, windowTitleContains: nil))
        savePreferences()
        refreshList()
        SettingsWindow.shared?.open(.exception(items.count - 1))
    }

    // MARK: - Exception page

    /// Builds the page for `.exception(i)`; nil for any other page or an exception that no longer exists.
    static func detailPage(_ page: SettingsPage) -> (title: String, view: NSView)? {
        guard case .exception(let index) = page, items.indices.contains(index) else { return nil }
        let entry = items[index]
        let info = resolvedApps[entry.bundleIdentifier] ?? AppDisplayInfo.resolve(bundleId: entry.bundleIdentifier)
        resolvedApps[entry.bundleIdentifier] = info

        let editor = ExceptionEditorView()
        let remove = NSButton(title: labelRemove, target: self, action: #selector(removeClicked(_:)))
        remove.bezelStyle = .rounded
        remove.hasDestructiveAction = true
        remove.tag = index
        let removeRow = NSStackView(views: [remove])
        let pageView = NSStackView(views: [makeDetailHeader(info, entry), editor, removeRow])
        pageView.orientation = .vertical
        pageView.alignment = .leading
        pageView.spacing = 20
        pageView.setCustomSpacing(14, after: editor)
        pageView.translatesAutoresizingMaskIntoConstraints = false
        editor.widthAnchor.constraint(equalToConstant: SettingsWindow.contentWidth).isActive = true

        editor.bind(to: entry) { [weak pageView] updated in
            guard items.indices.contains(index) else { return }
            let previous = items[index]
            items[index] = updated
            savePreferences()
            refreshList()
            guard let pageView, let oldHeader = pageView.arrangedSubviews.first else { return }
            if previous.bundleIdentifier != updated.bundleIdentifier {
                resolvedApps[updated.bundleIdentifier] = AppDisplayInfo.resolve(bundleId: updated.bundleIdentifier)
            }
            let info = resolvedApps[updated.bundleIdentifier] ?? AppDisplayInfo(name: updated.bundleIdentifier, icon: AppDisplayInfo.genericIcon)
            let newHeader = makeDetailHeader(info, updated)
            pageView.removeArrangedSubview(oldHeader)
            oldHeader.removeFromSuperview()
            pageView.insertArrangedSubview(newHeader, at: 0)
        }
        return (info.name, pageView)
    }

    /// The app's icon and name, with a summary of what applies to it.
    private static func makeDetailHeader(_ info: AppDisplayInfo, _ entry: ExceptionEntry) -> NSView {
        SettingsWindow.makePageHeader(tile: info.icon, keys: nil, title: info.name,
                                      description: ExceptionSummary.text(hide: entry.hide, ignore: entry.ignore))
    }

    @objc private static func removeClicked(_ sender: NSButton) {
        let index = sender.tag
        guard items.indices.contains(index) else { return }
        let name = resolvedApps[items[index].bundleIdentifier]?.name ?? items[index].bundleIdentifier
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: NSLocalizedString("Remove the exception for %@?", comment: ""), name)
        alert.informativeText = NSLocalizedString("CmdTab will treat this app like any other.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Remove", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        guard alert.runAttached(to: SettingsWindow.shared) == .alertFirstButtonReturn, items.indices.contains(index) else { return }
        items.remove(at: index)
        savePreferences()
        refreshList()
        SettingsWindow.shared?.removePages(where: {
            if case .exception(let j) = $0 { return j >= index }
            return false
        }, fallback: .section("exceptions"))
    }
}

struct AppDisplayInfo {
    let name: String
    let icon: NSImage

    static let genericIcon: NSImage = NSWorkspace.shared.icon(for: .application)

    static func resolve(bundleId: String) -> AppDisplayInfo {
        guard !bundleId.isEmpty else {
            return AppDisplayInfo(name: bundleId, icon: genericIcon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return fromBundle(at: url, fallbackName: bundleId)
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
           let path = running.bundleURL?.path {
            return AppDisplayInfo(name: running.localizedName ?? bundleId, icon: NSWorkspace.shared.icon(forFile: path))
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier ?? "").hasPrefix(bundleId)
        }), let path = running.bundleURL?.path {
            return AppDisplayInfo(name: bundleId, icon: NSWorkspace.shared.icon(forFile: path))
        }
        if let match = installedApps.first(where: { $0.bundleId.hasPrefix(bundleId) }) {
            return AppDisplayInfo(name: bundleId, icon: NSWorkspace.shared.icon(forFile: match.url.path))
        }
        return AppDisplayInfo(name: bundleId, icon: genericIcon)
    }

    private static func fromBundle(at url: URL, fallbackName: String) -> AppDisplayInfo {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let bundle = Bundle(url: url)
        let name = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? fallbackName
        return AppDisplayInfo(name: name, icon: icon)
    }

    // Cached on first access. Enumerates .app bundles in standard app directories.
    // .skipsPackageDescendants stops the enumerator from descending into .app packages but still
    // yields the .app URL itself, so nested apps (e.g. /Applications/Parallels/*.app) are found.
    private static let installedApps: [(bundleId: String, url: URL)] = {
        var apps: [(String, URL)] = []
        let dirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        let fm = FileManager.default
        for dir in dirs {
            guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let item = enumerator.nextObject() as? URL {
                guard item.pathExtension == "app", let bundleId = Bundle(url: item)?.bundleIdentifier else { continue }
                apps.append((bundleId, item))
            }
        }
        return apps
    }()
}
