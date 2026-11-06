import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

/// The Shortcuts page: the list of shortcuts (each opening its own page) and the trackpad gesture,
/// the keys that work while the switcher is open, and how the selection moves. Also keeps the
/// global shortcut-registry logic (`shortcuts` dict, `addShortcut` / `removeShortcutIfExists` /
/// `applyShortcutPreference`) and the arrow/vim helper callbacks consumed by other modules.
class ShortcutsTab {
    // MARK: - Public runtime state consumed by other modules

    /// Runtime model of all globally-bound shortcuts, keyed by their identifier
    /// (`holdShortcut0`, `nextWindowShortcut2`, etc.). Driven by `applyShortcutPreference`.
    /// Read by KeyboardEvents, KeyRepeatTimer, ATShortcut, TilesView, CustomRecorderControl,
    /// and the conflict detectors.
    static var shortcuts = [String: ATShortcut]()

    /// UI lookup: for any recorder currently displayed in Settings, its (control, label string).
    /// Populated by `makeRecorder` (the "While the switcher is open" keys) and by
    /// `TriggerBinding.bind` (the shortcut being edited). Operations on other shortcuts go through
    /// `Preferences` directly.
    static var shortcutControls = [String: (CustomRecorderControl, String)]()

    static var arrowKeysCheckbox: Switch!
    static var vimKeysCheckbox: Switch!

    // MARK: - Labels

    private static let labelAddShortcut = NSLocalizedString("Add Shortcut…", comment: "")
    private static let labelNotSet = NSLocalizedString("Not set", comment: "A shortcut with no key yet")
    private static let labelOff = NSLocalizedString("Off", comment: "The trackpad gesture is turned off")
    private static let labelArrowKeys = NSLocalizedString("Arrow keys", comment: "")
    private static let labelVimKeys = NSLocalizedString("Vim keys (H J K L)", comment: "")

    private static let staticManagedShortcutPreferences = [
        "focusWindowShortcut", "previousWindowShortcut", "searchShortcut",
        "closeWindowShortcut", "minDeminWindowShortcut", "toggleFullscreenWindowShortcut",
        "hideShowAppShortcut", "quitAppShortcut", "cancelShortcut",
    ]
    /// Canonical id → label for the keys that work while the switcher is open. Single source of
    /// truth: the "While the switcher is open" rows read their titles from here, and
    /// `conflictLabel(_:)` uses it to name a conflicting shortcut.
    static let staticShortcutLabels = [
        "focusWindowShortcut": NSLocalizedString("Open the selected window", comment: ""),
        "previousWindowShortcut": NSLocalizedString("Select the previous window", comment: ""),
        "searchShortcut": NSLocalizedString("Search", comment: ""),
        "closeWindowShortcut": NSLocalizedString("Close the window", comment: ""),
        "minDeminWindowShortcut": NSLocalizedString("Minimize or restore", comment: ""),
        "toggleFullscreenWindowShortcut": NSLocalizedString("Enter or exit fullscreen", comment: ""),
        "hideShowAppShortcut": NSLocalizedString("Hide or show the app", comment: ""),
        "quitAppShortcut": NSLocalizedString("Quit the app", comment: ""),
        "cancelShortcut": NSLocalizedString("Close the switcher", comment: ""),
    ]
    private static let removableShortcutPreferences = [
        "holdShortcut", "nextWindowShortcut",
        "appsToShow", "spacesToShow", "screensToShow",
        "showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows", "showWindowlessApps",
        "windowOrder", "shortcutStyle",
        "showAppsOrWindows", "showTabsAsWindows",
        "appearanceStyleOverride", "appearanceSizeOverride", "appearanceThemeOverride",
        "shortcutStyleOverride", "previewFocusedWindowOverride",
    ]
    private static let arrowKeys = ["←", "→", "↑", "↓"]
    private static let arrowKeyCodes: Set<KeyCode> = [.leftArrow, .rightArrow, .upArrow, .downArrow]
    private static let vimKeyActions = [
        "h": "vimCycleLeft",
        "l": "vimCycleRight",
        "k": "vimCycleUp",
        "j": "vimCycleDown",
    ]
    private static let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]

    // MARK: - Page state

    /// Holds the shortcuts list group; rebuilt by `refreshList` when a row's content changes.
    private static weak var listContainer: SeparatelyIndexedView?
    private static weak var addShortcutButton: NSButton?
    /// What the list shows now, so `refreshList` only rebuilds when something changed.
    private static var shownListEntries = [ListEntry]()
    /// The rows' titles and subtitles, published to search by `registerListSearchContent`.
    private static var listTitleLabels = [LightLabel]()
    private static var listSubtitleLabels = [NSTextField]()

    private struct ListEntry: Equatable {
        let index: Int
        let name: String
        let subtitle: String?
        /// Keycaps on the right; nil shows `value` as text instead.
        let keys: [String]?
        let value: String?
    }

    // MARK: - Initialization / teardown

    static func initializePreferencesDependentState() {
        applyActiveShortcutPreferences()
        staticManagedShortcutPreferences.forEach { applyShortcutPreference($0) }
        applyArrowKeysPreferenceWithoutDialogs()
        applyVimKeysPreferenceWithoutDialogs()
    }

    static func initTab() -> NSView {
        let width = SettingsWindow.contentWidth
        let list = SeparatelyIndexedView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        listContainer = list
        shownListEntries = []
        let add = NSButton(title: labelAddShortcut, target: self, action: #selector(addShortcutClicked))
        add.bezelStyle = .rounded
        addShortcutButton = add
        let top = NSStackView(views: [list, add])
        top.orientation = .vertical
        top.alignment = .leading
        top.spacing = 10
        list.widthAnchor.constraint(equalToConstant: width).isActive = true

        // Settings on each shortcut's own page: found by search from this section.
        // Per-shortcut settings are listed once, opening the first shortcut's page.
        SettingsSearchIndex.registerDetailStrings(ShortcutDetailPage.searchableStrings) {
            (.shortcut(0), ShortcutDetailPage.title(0))
        }

        let view = NSStackView(views: [top, makeTrackpadGroup(width), makeWhileOpenGroup(width), makeMovingGroup(width)])
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 22
        view.translatesAutoresizingMaskIntoConstraints = false
        refreshList()
        return view
    }

    static func cleanup() {
        arrowKeysCheckbox = nil
        vimKeysCheckbox = nil
        shortcutControls.removeAll()
        listContainer = nil
        addShortcutButton = nil
        shownListEntries = []
        listTitleLabels = []
        listSubtitleLabels = []
    }

    /// Shortcut pages (and the gesture's) are built by `ShortcutDetailPage` each time they open.
    static func registerDetailPages(in window: SettingsWindow) {
        window.registerDetailPages { page in
            guard case .shortcut(let index) = page,
                  index == Preferences.gestureIndex || (0..<Preferences.shortcutCount).contains(index) else { return nil }
            return ShortcutDetailPage.make(index: index, width: SettingsWindow.contentWidth)
        }
    }

    // MARK: - Groups

    private static func makeTrackpadGroup(_ width: CGFloat) -> TableGroupView {
        let group = TableGroupView(heading: NSLocalizedString("Trackpad", comment: ""), width: width)
        let haptic = NSLocalizedString("Haptic feedback", comment: "")
        group.addRow(leftText: haptic, rightViews: [labeled(LabelAndControl.makeSwitch("trackpadHapticFeedbackEnabled"), haptic)])
        return group
    }

    private static func makeWhileOpenGroup(_ width: CGFloat) -> NSView {
        let group = TableGroupView(heading: NSLocalizedString("While the switcher is open", comment: ""), width: width)
        for id in staticManagedShortcutPreferences {
            let label = staticShortcutLabels[id]!
            var views: [NSView] = [makeRecorder(id, label)]
            if id == "previousWindowShortcut" {
                views.insert(secondaryText(NSLocalizedString("hold", comment: "e.g. hold ⇧ to select the previous window")), at: 0)
            }
            group.addRow(leftText: label, rightViews: views)
        }
        let hint = NSStackView(views: [secondaryText(NSLocalizedString("Click a key to change it.", comment: ""), font: TableGroupView.subtitleFont)])
        hint.edgeInsets = NSEdgeInsets(top: 0, left: TableGroupView.rowHorizontalPadding, bottom: 0, right: TableGroupView.rowHorizontalPadding)
        let stack = NSStackView(views: [group, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        return stack
    }

    private static func makeMovingGroup(_ width: CGFloat) -> TableGroupView {
        let group = TableGroupView(heading: NSLocalizedString("Moving the selection", comment: ""), width: width)
        let arrows = labeled(LabelAndControl.makeSwitch("arrowKeysEnabled", extraAction: arrowKeysEnabledCallback), labelArrowKeys)
        let vim = labeled(LabelAndControl.makeSwitch("vimKeysEnabled", extraAction: vimKeysEnabledCallback), labelVimKeys)
        arrowKeysCheckbox = arrows
        vimKeysCheckbox = vim
        arrowKeysEnabledCallback(arrows)
        vimKeysEnabledCallback(vim)
        group.addRow(leftText: labelArrowKeys, rightViews: [arrows])
        group.addRow(leftText: labelVimKeys, rightViews: [vim])
        let mouse = NSLocalizedString("Mouse hover", comment: "")
        group.addRow(leftText: mouse, rightViews: [labeled(LabelAndControl.makeSwitch("mouseHoverEnabled"), mouse)])
        let pointer = NSLocalizedString("Move the pointer to the focused window", comment: "")
        group.addRow(leftText: pointer, rightViews: [labeled(LabelAndControl.makeDropdown("cursorFollowFocus", CursorFollowFocus.allCases), pointer)])
        return group
    }

    /// A key recorder for one of the "While the switcher is open" keys. Recording a key goes
    /// through the recorder's conflict handling, then is saved and applied.
    private static func makeRecorder(_ id: String, _ label: String) -> CustomRecorderControl {
        let recorder = CustomRecorderControl(Preferences.shortcut(id), true, id)
        _ = LabelAndControl.setupControl(recorder, id, extraAction: { _ in shortcutChangedCallback(recorder) })
        shortcutChangedCallback(recorder)
        shortcutControls[id] = (recorder, label)
        recorder.setAccessibilityLabel(label)
        return recorder
    }

    private static func secondaryText(_ text: String, font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = .secondaryLabelColor
        return field
    }

    private static func labeled<T: NSView>(_ view: T, _ label: String) -> T {
        view.setAccessibilityLabel(label)
        return view
    }

    // MARK: - Shortcuts list

    /// The current shortcuts as `ShortcutNaming` sees them. A shortcut with no key yet is named
    /// after its slot ("Shortcut 2"), so two unset shortcuts still get different names.
    static func inputsForNaming() -> [ShortcutNamingInput] {
        let apps = Preferences.appsToShow
        let spaces = Preferences.spacesToShow
        return (0..<Preferences.shortcutCount).map { index in
            ShortcutNamingInput(appsIndex: AppsToShowPreference.allCases.firstIndex(of: apps[index]) ?? 0,
                                spacesIndex: SpacesToShowPreference.allCases.firstIndex(of: spaces[index]) ?? 0,
                                keys: keys(index) ?? notSetKeys(index))
        }
    }

    /// The shortcut's keys (e.g. "⌘⇥"), or nil while it has no key to press.
    static func keys(_ index: Int) -> String? {
        let hold = Preferences.shortcut(Preferences.indexToName("holdShortcut", index))?.keyEquivalent ?? ""
        let next = Preferences.shortcut(Preferences.indexToName("nextWindowShortcut", index))?.keyEquivalent ?? ""
        return next.isEmpty ? nil : hold + next
    }

    private static func notSetKeys(_ index: Int) -> String {
        NSLocalizedString("Shortcut", comment: "") + " " + String(index + 1)
    }

    /// One keycap per modifier, then one for the key: "⌘⇧⇥" → ["⌘", "⇧", "⇥"].
    static func keycapGlyphs(_ keys: String) -> [String] {
        var glyphs = [String]()
        var rest = Substring(keys)
        while rest.count > 1, let first = rest.first, modifierGlyphs.contains(first) {
            glyphs.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { glyphs.append(String(rest)) }
        return glyphs
    }

    private static func listEntries() -> [ListEntry] {
        let inputs = inputsForNaming()
        let names = ShortcutNaming.names(inputs)
        var entries = inputs.enumerated().map { index, input in
            let shortcutKeys = keys(index)
            return ListEntry(index: index, name: names[index], subtitle: ShortcutNaming.subtitle(input),
                             keys: shortcutKeys.map { keycapGlyphs($0) }, value: shortcutKeys == nil ? labelNotSet : nil)
        }
        let gesture = Preferences.nextWindowGesture
        let gestureIndex = Preferences.gestureIndex
        let gestureSubtitle = gesture == .disabled ? nil : ShortcutNaming.subtitle(ShortcutNamingInput(
            appsIndex: AppsToShowPreference.allCases.firstIndex(of: Preferences.appsToShow[gestureIndex]) ?? 0,
            spacesIndex: SpacesToShowPreference.allCases.firstIndex(of: Preferences.spacesToShow[gestureIndex]) ?? 0,
            keys: ShortcutNaming.gestureName))
        entries.append(ListEntry(index: gestureIndex, name: ShortcutNaming.gestureName, subtitle: gestureSubtitle,
                                 keys: nil, value: gesture == .disabled ? labelOff : gesture.localizedString))
        return entries
    }

    /// Rebuilds the shortcuts list if a name, subtitle or key changed, and enables Add Shortcut…
    /// while there is room for another shortcut.
    static func refreshList() {
        addShortcutButton?.isEnabled = Preferences.shortcutCount < Preferences.maxShortcutCount
        guard let list = listContainer else { return }
        let entries = listEntries()
        guard entries != shownListEntries else { return }
        shownListEntries = entries
        let update = {
            list.arrangedSubviews.forEach { $0.removeFromSuperview() }
            // Not indexed here: `registerListSearchContent` publishes the rows, so search never
            // keeps strings or targets of rows that were replaced.
            let group = SettingsSearchIndex.unindexed { makeListGroup(entries) }
            list.addArrangedSubview(group)
        }
        if let window = SettingsWindow.shared {
            window.preserveScrollPosition(during: update)
        } else {
            update()
        }
        SettingsWindow.shared?.refreshSectionSearchContent("shortcuts")
    }

    private static func makeListGroup(_ entries: [ListEntry]) -> TableGroupView {
        let group = TableGroupView(heading: nil, width: SettingsWindow.contentWidth)
        listTitleLabels = []
        listSubtitleLabels = []
        for entry in entries {
            let accessory: NSView
            if let keys = entry.keys {
                accessory = LabelAndControl.makeKeycaps(keys)
            } else {
                accessory = secondaryText(entry.value ?? "")
            }
            let index = entry.index
            let row = group.addNavigationRow(title: entry.name, subtitle: entry.subtitle, accessory: accessory) {
                SettingsWindow.shared?.open(.shortcut(index))
            }
            listTitleLabels += (row.leftViews ?? []).compactMap { $0 as? LightLabel }
            if let subtitle = row.subtitleLabel { listSubtitleLabels.append(subtitle) }
        }
        return group
    }

    /// Publishes the list rows' titles and subtitles to search. Invoked by
    /// `SettingsWindow.refreshSectionSearchContent("shortcuts")` inside a fresh `indexed { }` scope,
    /// at build time and after every rebuild of the list.
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

    @objc private static func addShortcutClicked() {
        guard let index = addShortcutSlot() else { return }
        SettingsWindow.shared?.open(.shortcut(index))
    }

    /// Adds a shortcut at the end, holding ⌘ with no key yet. Returns its index.
    private static func addShortcutSlot() -> Int? {
        let currentCount = Preferences.shortcutCount
        guard currentCount < Preferences.maxShortcutCount else { return nil }
        resetShortcutPreferences(currentCount)
        setAddedShortcutTriggerDefaults(currentCount)
        Preferences.set("shortcutCount", String(currentCount + 1))
        initializeShortcutRecorderState(currentCount)
        return currentCount
    }

    /// Removes the shortcut at `index`; the ones after it move up one slot. Used by the shortcut's
    /// own page.
    static func removeShortcut(at index: Int) {
        let currentCount = Preferences.shortcutCount
        guard currentCount > Preferences.minShortcutCount, (0..<currentCount).contains(index) else { return }
        if index < currentCount - 1 {
            for i in index..<(currentCount - 1) {
                copyShortcutPreferences(i + 1, i)
            }
        }
        resetShortcutPreferences(currentCount - 1)
        Preferences.set("shortcutCount", String(currentCount - 1))
    }

    private static func resetShortcutPreferences(_ index: Int) {
        removableShortcutPreferences.forEach {
            Preferences.remove(Preferences.indexToName($0, index), false)
        }
    }

    private static func setAddedShortcutTriggerDefaults(_ index: Int) {
        Preferences.setShortcut(Preferences.indexToName("holdShortcut", index), keyEquivalent: "⌘", false)
        Preferences.setShortcut(Preferences.indexToName("nextWindowShortcut", index), keyEquivalent: "", false)
        Preferences.set(Preferences.indexToName("appsToShow", index), AppsToShowPreference.all.indexAsString, false)
    }

    private static func copyShortcutPreferences(_ fromIndex: Int, _ toIndex: Int) {
        removableShortcutPreferences.forEach { baseName in
            let fromKey = Preferences.indexToName(baseName, fromIndex)
            let toKey = Preferences.indexToName(baseName, toIndex)
            if let value = Preferences.all[fromKey] {
                UserDefaults.standard.set(value, forKey: toKey)
                CachedUserDefaults.removeFromCache(toKey)
                Preferences.invalidateAllCache()
            } else {
                Preferences.remove(toKey, false)
            }
        }
    }

    // MARK: - Preference-change routing

    static func preferenceChanged(_ key: String) {
        switch key {
        case "shortcutCount":
            applyActiveShortcutPreferences()
            (0..<Preferences.shortcutCount).forEach { initializeShortcutRecorderState($0) }
            refreshList()
        case "nextWindowGesture":
            refreshList()
        case let k where isShortcutPreferenceKey(k):
            if Preferences.nameToIndex(k) < Preferences.shortcutCount {
                applyShortcutPreference(k)
            } else {
                removeShortcutIfExists(k)
            }
            refreshList()
        case let k where isNamingPreferenceKey(k):
            refreshList()
        case let k where staticManagedShortcutPreferences.contains(k):
            applyShortcutPreference(k)
        case let k where Preferences.overrideToGlobalKey.values.contains(k):
            AppearanceTab.refreshLookNote()
            if k == "appearanceStyle" { AppearanceTab.refreshStyleDependentRows() }
        case let k where isOverrideKey(k):
            AppearanceTab.refreshLookNote()
        case "arrowKeysEnabled" where arrowKeysCheckbox == nil:
            applyArrowKeysPreferenceWithoutDialogs()
        case "vimKeysEnabled" where vimKeysCheckbox == nil:
            applyVimKeysPreferenceWithoutDialogs()
        default:
            break
        }
    }

    static func inputSourceChanged() {
        refreshList()
        refreshShortcutControlsDisplay()
    }

    // MARK: - Key helpers

    private static func isOverrideKey(_ key: String) -> Bool {
        Preferences.appearanceOverrideBaseNames.contains { baseName in
            (0...Preferences.maxShortcutCount).contains { Preferences.indexToName(baseName, $0) == key }
        }
    }

    private static func isShortcutPreferenceKey(_ key: String) -> Bool {
        return (0..<Preferences.maxShortcutCount).contains(where: { index in
            ["holdShortcut", "nextWindowShortcut"].contains { key == Preferences.indexToName($0, index) }
        })
    }

    /// The per-shortcut settings a list row's name and subtitle come from.
    private static func isNamingPreferenceKey(_ key: String) -> Bool {
        (0...Preferences.maxShortcutCount).contains { index in
            ["appsToShow", "spacesToShow"].contains { key == Preferences.indexToName($0, index) }
        }
    }

    // MARK: - Shortcut registry (global keyboard binding)

    private static func applyActiveShortcutPreferences() {
        (0..<Preferences.maxShortcutCount).forEach { index in
            ["holdShortcut", "nextWindowShortcut"].forEach { base in
                let key = Preferences.indexToName(base, index)
                if index < Preferences.shortcutCount {
                    applyShortcutPreference(key)
                } else {
                    removeShortcutIfExists(key)
                }
            }
        }
    }

    private static func addShortcut(_ triggerPhase: ShortcutTriggerPhase, _ scope: ShortcutScope, _ shortcut: Shortcut, _ controlId: String, _ index: Int?) {
        let atShortcut = ATShortcut(shortcut, controlId, scope, triggerPhase, index)
        removeShortcutIfExists(controlId)
        shortcuts[controlId] = atShortcut
        if scope == .global {
            KeyboardEvents.addGlobalShortcut(controlId, atShortcut.shortcut)
            ShortcutsTab.toggleNativeCommandTabIfNeeded()
        }
        recomputeEscapeAbsorption()
    }

    /// The shared cghidEventTap absorbs Esc keyDown only when a configured shortcut
    /// binds Escape; otherwise Esc passes through to the active app unchanged.
    static func recomputeEscapeAbsorption() {
        KeyboardEvents.anyShortcutUsesEscape = shortcuts.values.contains { $0.shortcut.carbonKeyCode == kVK_Escape }
        KeyboardEvents.updateEscapeAbsorptionTap()
    }

    /// Thin adapter over `NativeHotkeyResolver.resolve` — builds the snapshot inputs from the live
    /// shortcut registry and applies the resolver's verdict via the symbolic-hotkey API. See
    /// `NativeHotkeyResolverSpecs.md` for the kernel's invariants and the native-⌘⇥-override bug's root cause.
    static func toggleNativeCommandTabIfNeeded() {
        let snapshots = shortcuts.values.map { ShortcutSnapshot(modifiers: $0.shortcut.carbonModifierFlags, keyCode: $0.shortcut.carbonKeyCode) }
        let holdShortcutModifiers: [UInt32] = (0..<Preferences.holdShortcut.count).compactMap { i in
            shortcuts[Preferences.indexToName("holdShortcut", i)]?.shortcut.carbonModifierFlags
        }
        let result = NativeHotkeyResolver.resolve(shortcuts: snapshots, holdShortcutModifiers: holdShortcutModifiers)
        setNativeCommandTabEnabled(false, Array(result.disable))
        setNativeCommandTabEnabled(true, Array(result.enable))
    }

    @objc static func shortcutChangedCallback(_ sender: NSControl) {
        let controlId = sender.identifier!.rawValue
        if isShortcutPreferenceKey(controlId) && Preferences.nameToIndex(controlId) >= Preferences.shortcutCount {
            return
        }
        if controlId.hasPrefix("holdShortcut") {
            let i = Preferences.nameToIndex(controlId)
            guard let shortcut = Preferences.shortcut(controlId) else {
                removeShortcutIfExists(controlId)
                return
            }
            addShortcut(.up, .global, shortcut, controlId, i)
            if let nextWindowShortcut = shortcutControls[Preferences.indexToName("nextWindowShortcut", i)]?.0 {
                nextWindowShortcut.restrictModifiers([(sender as! CustomRecorderControl).objectValue!.modifierFlags])
                shortcutChangedCallback(nextWindowShortcut)
            }
        } else {
            let newShortcut = combineHoldAndNextWindow(controlId, sender)
            if newShortcut == nil {
                removeShortcutIfExists(controlId)
                restrictModifiersOfHoldShortcut(controlId, [])
                (sender as! CustomRecorderControl).objectValue = nil
            } else {
                addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, newShortcut!, controlId, nil)
                restrictModifiersOfHoldShortcut(controlId, [(sender as! CustomRecorderControl).objectValue!.modifierFlags])
            }
        }
    }

    private static func restrictModifiersOfHoldShortcut(_ controlId: String, _ modifiers: NSEvent.ModifierFlags) {
        if controlId.hasPrefix("nextWindowShortcut") {
            let i = Preferences.nameToIndex(controlId)
            if let holdShortcut = shortcutControls[Preferences.indexToName("holdShortcut", i)]?.0 {
                holdShortcut.restrictModifiers(modifiers)
            }
        }
    }

    static func combineHoldAndNextWindow(_ controlId: String, _ sender: NSControl) -> Shortcut? {
        guard let baseShortcut = (sender as! RecorderControl).objectValue else { return nil }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = Preferences.shortcut(Preferences.indexToName("holdShortcut", Preferences.nameToIndex(controlId)))
            return combineShortcuts(holdShortcut, baseShortcut)
        }
        return baseShortcut
    }

    @objc static func arrowKeysEnabledCallback(_ sender: NSControl) {
        if (sender as! Switch).state == .on {
            if isClearArrowKeysSuccessful() {
                arrowKeys.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $0, nil) }
            } else {
                (sender as! Switch).state = .off
                Preferences.set("arrowKeysEnabled", "false", false)
            }
        } else {
            arrowKeys.forEach { removeShortcutIfExists($0) }
        }
    }

    private static func isClearArrowKeysSuccessful() -> Bool {
        var conflicts = [String: String]()
        shortcuts.forEach {
            guard arrowKeyCodes.contains($1.shortcut.keyCode) else { return }
            guard !arrowKeys.contains($1.id) else { return }
            if let label = conflictLabel($1.id) {
                conflicts[$1.id] = label
            }
        }
        if !conflicts.isEmpty {
            if SettingsWindow.shared == nil || !shouldClearConflictingShortcuts(conflicts.map { $0.value }, NSLocalizedString("Arrow keys already assigned to other actions:\n%@", comment: "")) {
                return false
            }
            conflicts.forEach { unassignShortcut($0.key) }
        }
        return true
    }

    @objc static func vimKeysEnabledCallback(_ sender: NSControl) {
        if (sender as! Switch).state == .on {
            if isClearVimKeysSuccessful() {
                vimKeyActions.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $1, nil) }
            } else {
                (sender as! Switch).state = .off
                Preferences.remove("vimKeysEnabled")
            }
        } else {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
        }
    }

    private static func isClearVimKeysSuccessful() -> Bool {
        var conflicts = [String: String]()
        shortcuts.forEach {
            let keymap = $1.shortcut.characters
            if keymap != nil && vimKeyActions.keys.contains(keymap!) {
                let control_id = $1.id
                guard !vimKeyActions.values.contains(control_id) else { return }
                if let label = conflictLabel(control_id) {
                    conflicts[control_id] = label
                }
            }
        }
        if !conflicts.isEmpty {
            if SettingsWindow.shared == nil || !shouldClearConflictingShortcuts(conflicts.map { $0.value }, NSLocalizedString("Vim keys already assigned to other actions:\n%@", comment: "")) {
                return false
            }
            conflicts.forEach { unassignShortcut($0.key) }
        }
        return true
    }

    /// Human-readable label for the action bound to `id`, resolved purely from the model — the id's
    /// shape plus `staticShortcutLabels` — NOT from `shortcutControls`. This is what lets the conflict
    /// dialog name a shortcut that isn't currently displayed in the recycled editor (which keeps only
    /// the on-screen shortcut in `shortcutControls`). Returns nil for ids with no known action.
    ///
    /// A numbered shortcut's hold and "and press" both resolve to that shortcut's automatic name
    /// (e.g. "Windows of the current app"), naming WHICH shortcut holds the keys.
    static func conflictLabel(_ id: String) -> String? {
        if arrowKeys.contains(id) { return labelArrowKeys }
        if vimKeyActions.values.contains(id) { return labelVimKeys }
        if id.hasPrefix("holdShortcut") || id.hasPrefix("nextWindowShortcut") {
            let index = Preferences.nameToIndex(id)
            let names = ShortcutNaming.names(inputsForNaming())
            return index < names.count ? names[index] : notSetKeys(index)
        }
        return staticShortcutLabels[id]
    }

    /// Clear the shortcut bound to `id` and let the normal preference-change pipeline reconcile the
    /// registry and UI. Used by the conflict dialog's "Unassign existing shortcut and continue" for a
    /// shortcut that may not be on screen, so it goes through `Preferences` (cached UserDefaults)
    /// rather than mutating a live recorder. If that recorder happens to be displayed, sync it too.
    ///
    /// For a numbered shortcut's Trigger the hold can't stand alone, so "unassign" clears the "and
    /// press" (nextWindowShortcut) part — e.g. ⌥+Tab becomes ⌥+(unassigned) — whether the conflict
    /// was reported against the hold or the press.
    static func unassignShortcut(_ id: String) {
        let keyToClear = (id.hasPrefix("holdShortcut") || id.hasPrefix("nextWindowShortcut"))
            ? Preferences.indexToName("nextWindowShortcut", Preferences.nameToIndex(id))
            : id
        Preferences.setShortcut(keyToClear, nil)
        shortcutControls[keyToClear]?.0.objectValue = nil
    }

    private static func shouldClearConflictingShortcuts(_ conflicts: [String], _ messageFormat: String) -> Bool {
        let list = conflicts.map { "• " + $0 }.joined(separator: "\n")
        return confirmUnassigningConflict(String(format: messageFormat, nonBreaking(list)))
    }

    /// The prompt both conflict detectors raise: unassign whatever holds the shortcut, or cancel
    /// (Esc). `true` means the user chose to unassign. It is a sheet on `window`, which defaults to Settings.
    static func confirmUnassigningConflict(_ informativeText: String, in window: NSWindow? = SettingsWindow.shared) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = informativeText
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: "")).setAccessibilityFocused(true)
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        return alert.runAttached(to: window) == .alertFirstButtonReturn
    }

    /// An action's name must not be split across lines by the alert's own wrapping.
    static func nonBreaking(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    private static func removeShortcutIfExists(_ controlId: String) {
        if let atShortcut = shortcuts[controlId] {
            if atShortcut.scope == .global {
                KeyboardEvents.removeGlobalShortcut(controlId, atShortcut.shortcut)
            }
            shortcuts.removeValue(forKey: controlId)
            if atShortcut.scope == .global {
                ShortcutsTab.toggleNativeCommandTabIfNeeded()
            }
            recomputeEscapeAbsorption()
        }
    }

    private static func applyShortcutPreference(_ controlId: String) {
        if isShortcutPreferenceKey(controlId) && Preferences.nameToIndex(controlId) >= Preferences.shortcutCount {
            removeShortcutIfExists(controlId)
            return
        }
        if controlId.hasPrefix("holdShortcut") {
            applyHoldShortcutPreference(controlId)
            applyShortcutPreference(Preferences.indexToName("nextWindowShortcut", Preferences.nameToIndex(controlId)))
            return
        }
        guard let shortcut = combinedShortcut(controlId) else {
            removeShortcutIfExists(controlId)
            restrictModifiersOfHoldShortcut(controlId, [])
            return
        }
        addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, shortcut, controlId, nil)
        restrictModifiersOfHoldShortcut(controlId, [shortcut.modifierFlags])
    }

    private static func applyHoldShortcutPreference(_ controlId: String) {
        let i = Preferences.nameToIndex(controlId)
        guard let shortcut = Preferences.shortcut(controlId) else {
            removeShortcutIfExists(controlId)
            return
        }
        addShortcut(.up, .global, shortcut, controlId, i)
    }

    private static func combinedShortcut(_ controlId: String) -> Shortcut? {
        guard let baseShortcut = Preferences.shortcut(controlId) else { return nil }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = Preferences.shortcut(Preferences.indexToName("holdShortcut", Preferences.nameToIndex(controlId)))
            return combineShortcuts(holdShortcut, baseShortcut)
        }
        return baseShortcut
    }

    private static func combineShortcuts(_ holdShortcut: Shortcut?, _ baseShortcut: Shortcut) -> Shortcut {
        guard let holdShortcut else { return baseShortcut }
        return Shortcut(code: baseShortcut.keyCode, modifierFlags: [holdShortcut.modifierFlags, baseShortcut.modifierFlags], characters: baseShortcut.characters, charactersIgnoringModifiers: baseShortcut.charactersIgnoringModifiers)
    }

    private static func applyArrowKeysPreferenceWithoutDialogs() {
        guard Preferences.arrowKeysEnabled else {
            arrowKeys.forEach { removeShortcutIfExists($0) }
            return
        }
        if hasArrowKeysConflictWithoutUi() {
            arrowKeys.forEach { removeShortcutIfExists($0) }
            Preferences.set("arrowKeysEnabled", "false", false)
            return
        }
        arrowKeys.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $0, nil) }
    }

    private static func hasArrowKeysConflictWithoutUi() -> Bool {
        return shortcuts.values.contains {
            guard arrowKeyCodes.contains($0.shortcut.keyCode) else { return false }
            return !arrowKeys.contains($0.id)
        }
    }

    private static func applyVimKeysPreferenceWithoutDialogs() {
        guard Preferences.vimKeysEnabled else {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
            return
        }
        if hasVimKeysConflictWithoutUi() {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
            Preferences.set("vimKeysEnabled", "false", false)
            return
        }
        vimKeyActions.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $1, nil) }
    }

    private static func hasVimKeysConflictWithoutUi() -> Bool {
        return shortcuts.values.contains {
            if let key = $0.shortcut.characters, vimKeyActions.keys.contains(key) {
                return !vimKeyActions.values.contains($0.id)
            }
            return false
        }
    }

    // MARK: - Recorder lifecycle

    private static func initializeShortcutRecorderState(_ index: Int) {
        guard index < Preferences.shortcutCount else { return }
        let holdControlId = Preferences.indexToName("holdShortcut", index)
        let nextControlId = Preferences.indexToName("nextWindowShortcut", index)
        if let holdShortcut = shortcutControls[holdControlId]?.0 {
            holdShortcut.objectValue = Preferences.shortcut(holdControlId)
            shortcutChangedCallback(holdShortcut)
        }
        if let nextWindowShortcut = shortcutControls[nextControlId]?.0 {
            nextWindowShortcut.objectValue = Preferences.shortcut(nextControlId)
            shortcutChangedCallback(nextWindowShortcut)
        }
    }

    private static func refreshShortcutControlsDisplay() {
        shortcutControls.values.forEach {
            $0.0.needsDisplay = true
            $0.0.invalidateIntrinsicContentSize()
        }
    }
}

