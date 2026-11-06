import Cocoa
import ShortcutRecorder

// The groups of a shortcut's own page (see `ShortcutDetailPage`). Each is bound to one shortcut
// with `bind(toShortcut:)`; the page is rebuilt every time it opens.

// MARK: - Shortcut row (hold + then-press recorders)

/// "hold [⌘] then press [⇥]": two recorders bound to `holdShortcut`N and `nextWindowShortcut`N.
/// The next-window recorder is restricted to the modifiers of the hold key. While bound, both are
/// listed in `ShortcutsTab.shortcutControls` so the conflict handling finds them.
final class TriggerBinding {
    let view: NSView
    private let holdRecorder: CustomRecorderControl
    private let nextRecorder: CustomRecorderControl
    static let holdLabelText = NSLocalizedString("hold", comment: "hold ⌘ then press ⇥")
    static let thenPressText = NSLocalizedString("then press", comment: "hold ⌘ then press ⇥")
    private static let holdAccessibilityLabel = NSLocalizedString("Hold", comment: "")
    private static let nextAccessibilityLabel = NSLocalizedString("Then press", comment: "")
    /// Fixed height for the row's content: `RecorderControl`'s intrinsic height isn't guaranteed
    /// to be set when the row measures it.
    private static let contentHeight: CGFloat = 22
    private var currentIndex: Int = -1

    init() {
        // Placeholder identifier — replaced in bind().
        holdRecorder = CustomRecorderControl(nil, false, "holdShortcut0")
        nextRecorder = CustomRecorderControl(nil, true, "nextWindowShortcut0")
        holdRecorder.setAccessibilityLabel(TriggerBinding.holdAccessibilityLabel)
        nextRecorder.setAccessibilityLabel(TriggerBinding.nextAccessibilityLabel)

        let stack = NSStackView(views: [TriggerBinding.secondaryText(TriggerBinding.holdLabelText), holdRecorder,
                                        TriggerBinding.secondaryText(TriggerBinding.thenPressText), nextRecorder])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.heightAnchor.constraint(equalToConstant: TriggerBinding.contentHeight).isActive = true
        view = stack

        // A recorder edit is saved (so the list and the header read it back), re-registers the
        // global hotkey (cascading the modifier restriction to the sibling), then refreshes the list.
        holdRecorder.onAction = { [weak self] _ in
            guard let self else { return }
            LabelAndControl.controlWasChanged(self.holdRecorder, nil)
            ShortcutsTab.shortcutChangedCallback(self.holdRecorder)
            ShortcutsTab.refreshList()
        }
        nextRecorder.onAction = { [weak self] _ in
            guard let self else { return }
            LabelAndControl.controlWasChanged(self.nextRecorder, nil)
            ShortcutsTab.shortcutChangedCallback(self.nextRecorder)
            ShortcutsTab.refreshList()
        }
    }

    deinit {
        unregister()
    }

    private static func secondaryText(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.textColor = .secondaryLabelColor
        return field
    }

    /// Removes this binding's recorders from `shortcutControls`, unless another page took the keys.
    private func unregister() {
        guard currentIndex >= 0 else { return }
        for (base, recorder) in [("holdShortcut", holdRecorder), ("nextWindowShortcut", nextRecorder)] {
            let key = Preferences.indexToName(base, currentIndex)
            if ShortcutsTab.shortcutControls[key]?.0 === recorder {
                ShortcutsTab.shortcutControls.removeValue(forKey: key)
            }
        }
    }

    func bind(toShortcut index: Int) {
        unregister()
        currentIndex = index
        let holdKey = Preferences.indexToName("holdShortcut", index)
        let nextKey = Preferences.indexToName("nextWindowShortcut", index)
        holdRecorder.identifier = NSUserInterfaceItemIdentifier(holdKey)
        nextRecorder.identifier = NSUserInterfaceItemIdentifier(nextKey)
        holdRecorder.objectValue = Preferences.shortcut(holdKey)
        nextRecorder.objectValue = Preferences.shortcut(nextKey)
        ShortcutsTab.shortcutControls[holdKey] = (holdRecorder, TriggerBinding.holdAccessibilityLabel)
        ShortcutsTab.shortcutControls[nextKey] = (nextRecorder, TriggerBinding.nextAccessibilityLabel)
        // Reapply modifier restriction on the next-window recorder based on the hold shortcut.
        if let holdModifiers = Preferences.shortcut(holdKey)?.modifierFlags {
            nextRecorder.restrictModifiers(holdModifiers)
        } else {
            nextRecorder.restrictModifiers([])
        }
    }
}

// MARK: - Which windows to show

/// The "Which windows to show" group: per-shortcut filtering pop-ups.
final class FilteringPane {
    static let heading = NSLocalizedString("Which windows to show", comment: "")
    private static let labelApps = NSLocalizedString("Apps", comment: "")
    private static let labelSpaces = NSLocalizedString("Spaces", comment: "")
    private static let labelScreens = NSLocalizedString("Screens", comment: "")
    private static let labelMinimized = NSLocalizedString("Minimized windows", comment: "")
    private static let labelHidden = NSLocalizedString("Hidden windows", comment: "")
    private static let labelFullscreen = NSLocalizedString("Fullscreen windows", comment: "")
    private static let labelWindowless = NSLocalizedString("Apps with no open window", comment: "")

    /// Everything this group shows, for search from the Shortcuts section (the group itself lives
    /// on a page that is built only when opened).
    static let searchableStrings: [String] = [
        heading, labelApps, labelSpaces, labelScreens,
        labelMinimized, labelHidden, labelFullscreen, labelWindowless,
    ] + AppsToShowPreference.allCases.map { $0.localizedString }
      + SpacesToShowPreference.allCases.map { $0.localizedString }
      + ScreensToShowPreference.allCases.map { $0.localizedString }
      + ShowHowPreference.allCases.map { $0.localizedString }

    let view: NSView
    private let dropdowns: [ShortcutBoundDropdown]

    init(width: CGFloat) {
        let rows: [(String, ShortcutBoundDropdown)] = [
            (Self.labelApps, ShortcutBoundDropdown(baseName: "appsToShow", cases: AppsToShowPreference.allCases)),
            (Self.labelSpaces, ShortcutBoundDropdown(baseName: "spacesToShow", cases: SpacesToShowPreference.allCases)),
            (Self.labelScreens, ShortcutBoundDropdown(baseName: "screensToShow", cases: ScreensToShowPreference.allCases)),
            (Self.labelMinimized, ShortcutBoundDropdown(baseName: "showMinimizedWindows", cases: ShowHowPreference.allCases)),
            (Self.labelHidden, ShortcutBoundDropdown(baseName: "showHiddenWindows", cases: ShowHowPreference.allCases)),
            (Self.labelFullscreen, ShortcutBoundDropdown(baseName: "showFullscreenWindows", cases: ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })),
            (Self.labelWindowless, ShortcutBoundDropdown(baseName: "showWindowlessApps", cases: ShowHowPreference.allCases)),
        ]
        let group = TableGroupView(heading: Self.heading, width: width)
        for (label, dropdown) in rows {
            dropdown.setAccessibilityLabel(label)
            group.addRow(leftText: label, rightViews: [dropdown])
        }
        dropdowns = rows.map { $0.1 }
        view = group
    }

    func bind(toShortcut index: Int) {
        dropdowns.forEach { $0.bind(toShortcut: index) }
    }
}

// MARK: - Order and grouping

final class OrderingPane {
    static let heading = NSLocalizedString("Order and grouping", comment: "")
    private static let labelWindowOrder = NSLocalizedString("Order windows by", comment: "")
    private static let labelGroupApps = NSLocalizedString("Apps", comment: "")
    private static let labelGroupTabs = NSLocalizedString("Tabs", comment: "")

    /// See `FilteringPane.searchableStrings`.
    static let searchableStrings: [String] = [
        heading, labelWindowOrder, labelGroupApps, labelGroupTabs,
    ] + GroupAppsPreference.allCases.map { $0.localizedString }
      + GroupTabsPreference.allCases.map { $0.localizedString }
      + WindowOrderPreference.allCases.map { $0.localizedString }

    let view: NSView
    private let dropdowns: [ShortcutBoundDropdown]

    init(width: CGFloat) {
        let rows: [(String, ShortcutBoundDropdown)] = [
            (Self.labelWindowOrder, ShortcutBoundDropdown(baseName: "windowOrder", cases: WindowOrderPreference.allCases)),
            (Self.labelGroupApps, ShortcutBoundDropdown(baseName: "showAppsOrWindows", cases: GroupAppsPreference.allCases)),
            (Self.labelGroupTabs, ShortcutBoundDropdown(baseName: "showTabsAsWindows", cases: GroupTabsPreference.allCases)),
        ]
        let group = TableGroupView(heading: Self.heading, width: width)
        for (label, dropdown) in rows {
            dropdown.setAccessibilityLabel(label)
            group.addRow(leftText: label, rightViews: [dropdown])
        }
        dropdowns = rows.map { $0.1 }
        view = group
    }

    func bind(toShortcut index: Int) {
        dropdowns.forEach { $0.bind(toShortcut: index) }
    }
}

// MARK: - Look

/// The "Look" group: one switch, "Same as Appearance settings". Off, the group expands with this
/// shortcut's own style, size, theme, after-keys-released and preview controls, which write the
/// shortcut's `…Override` keys (see `ShortcutLook`).
final class AppearancePane {
    static let heading = NSLocalizedString("Look", comment: "")
    static let labelSameAsAppearance = NSLocalizedString("Same as Appearance settings", comment: "")
    static let subtitleSameAsAppearance = NSLocalizedString("Turn off to give this shortcut its own style, size and theme.", comment: "")

    /// See `FilteringPane.searchableStrings`.
    static let searchableStrings: [String] = [
        heading, labelSameAsAppearance, subtitleSameAsAppearance,
        AppearanceTab.labelSize,
        AppearanceTab.labelTheme,
        AppearanceTab.labelShortcutStyle,
        AppearanceTab.labelPreviewSelectedWindow,
    ] + AppearanceStylePreference.allCases.map { $0.localizedString }
      + AppearanceSizePreference.allCases.map { $0.localizedString }
      + AppearanceThemePreference.allCases.map { $0.localizedString }
      + ShortcutStylePreference.allCases.map { $0.localizedString }

    let view: NSView
    private let followSwitch: Switch
    /// The card holding the five controls, shown while the switch is off.
    private let controlsCard: NSView
    private let style: ShortcutOverrideRadios
    private let size: ShortcutOverrideSegmented
    private let theme: ShortcutOverrideSegmented
    private let shortcutStyle: ShortcutOverrideDropdown
    private let preview: ShortcutOverrideSwitch
    private var bindings: [ShortcutOverrideBinding] { [style, size, theme, shortcutStyle, preview] }
    private var currentIndex = 0

    init(width: CGFloat) {
        let onChange: () -> Void = {
            AppearanceTab.refreshLookNote()
            ShortcutsTab.refreshList()
        }
        style = ShortcutOverrideRadios(baseName: "appearanceStyleOverride", cases: AppearanceStylePreference.allCases, onChange: onChange)
        size = ShortcutOverrideSegmented(baseName: "appearanceSizeOverride", cases: AppearanceSizePreference.allCases, onChange: onChange)
        theme = ShortcutOverrideSegmented(baseName: "appearanceThemeOverride", cases: AppearanceThemePreference.allCases, onChange: onChange)
        shortcutStyle = ShortcutOverrideDropdown(baseName: "shortcutStyleOverride", cases: ShortcutStylePreference.allCases, onChange: onChange)
        preview = ShortcutOverrideSwitch(baseName: "previewFocusedWindowOverride", onChange: onChange)
        followSwitch = Switch(true)
        followSwitch.setAccessibilityLabel(Self.labelSameAsAppearance)

        let group = TableGroupView(heading: Self.heading, width: width)
        group.addRow(leftText: Self.labelSameAsAppearance, rightViews: [followSwitch], subText: Self.subtitleSameAsAppearance)
        let table = group.addNewTable()
        controlsCard = table.superview ?? table
        style.stack.widthAnchor.constraint(equalToConstant: width - 2 * (TableGroupView.borderWidth + TableGroupView.rowHorizontalPadding)).isActive = true
        group.addRow(leftViews: [style.stack])
        size.segmented.setAccessibilityLabel(AppearanceTab.labelSize)
        group.addRow(leftText: AppearanceTab.labelSize, rightViews: [size.segmented])
        theme.segmented.setAccessibilityLabel(AppearanceTab.labelTheme)
        group.addRow(leftText: AppearanceTab.labelTheme, rightViews: [theme.segmented])
        shortcutStyle.popUp.setAccessibilityLabel(AppearanceTab.labelShortcutStyle)
        group.addRow(leftText: AppearanceTab.labelShortcutStyle, rightViews: [shortcutStyle.popUp])
        preview.toggle.setAccessibilityLabel(AppearanceTab.labelPreviewSelectedWindow)
        group.addRow(leftText: AppearanceTab.labelPreviewSelectedWindow, rightViews: [preview.toggle])
        view = group

        followSwitch.onAction = { [weak self] control in
            self?.followSwitchToggled(on: (control as? NSButton)?.state == .on)
        }
    }

    /// The switch is on only when no override is stored for the shortcut. The controls show their
    /// effective values (the stored override, else the global); nothing is written here.
    func bind(toShortcut index: Int) {
        currentIndex = index
        let follows = ShortcutLook.followsAppearance(stored: Preferences.all, index: index)
        followSwitch.setSilently(follows ? .on : .off)
        bindings.forEach { $0.bind(toShortcut: index) }
        controlsCard.isHidden = follows
    }

    private func followSwitchToggled(on: Bool) {
        if on {
            ShortcutLook.keysToRemoveWhenTurnedOn(index: currentIndex).forEach { Preferences.remove($0) }
        } else {
            let writes = ShortcutLook.writesWhenTurnedOff(index: currentIndex) { global in
                UserDefaults.standard.string(forKey: global) ?? ""
            }
            writes.forEach { Preferences.set($0.key, $0.value) }
        }
        let update = { [self] in
            bindings.forEach { $0.bind(toShortcut: currentIndex) }
            controlsCard.isHidden = on
        }
        if let window = SettingsWindow.shared {
            window.preserveScrollPosition(during: update)
        } else {
            update()
        }
        AppearanceTab.refreshLookNote()
        ShortcutsTab.refreshList()
    }
}

// MARK: - Bindings: simple per-shortcut

/// A dropdown bound to a per-shortcut preference key (e.g. `appsToShow2`). On `bind`, swaps the
/// identifier and refreshes the selected item from UserDefaults. Writes go through the inherited
/// `onAction` → `LabelAndControl.controlWasChanged`, which reads the current identifier — so
/// `bind` is the only place we need to keep the binding consistent.
final class ShortcutBoundDropdown: PopupButtonLikeSystemSettings {
    private let baseName: String
    private let cases: [MacroPreference]

    init(baseName: String, cases: [MacroPreference]) {
        self.baseName = baseName
        self.cases = cases
        super.init(frame: .zero, pullsDown: false)
        addItems(withTitles: cases.map { $0.localizedString })
        // Identifier set in bind(); placeholder until then.
        identifier = NSUserInterfaceItemIdentifier(Preferences.indexToName(baseName, 0))
        onAction = { control in
            LabelAndControl.controlWasChanged(control, nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }

    func bind(toShortcut index: Int) {
        let key = Preferences.indexToName(baseName, index)
        identifier = NSUserInterfaceItemIdentifier(key)
        let selectedIndex = CachedUserDefaults.intFromMacroPref(key, cases)
        let clamped = max(0, min(selectedIndex, numberOfItems - 1))
        selectItem(at: clamped)
    }
}

// MARK: - Bindings: look overrides

/// A control bound to one of a shortcut's `…Override` keys (e.g. `appearanceSizeOverride2`). It
/// shows the effective value: the stored override, else the global. Choosing another value writes
/// the override key; choosing the value already shown writes nothing.
class ShortcutOverrideBinding {
    let baseName: String
    private(set) var currentShortcutIndex = 0
    private let onChange: (() -> Void)?

    init(baseName: String, onChange: (() -> Void)?) {
        self.baseName = baseName
        self.onChange = onChange
    }

    var key: String { Preferences.indexToName(baseName, currentShortcutIndex) }
    var globalKey: String { Preferences.overrideToGlobalKey[baseName] ?? baseName }
    /// The stored override if there is one, else the global's stored-or-default value.
    var effectiveValue: String? {
        if Preferences.hasOverride(baseName, currentShortcutIndex) {
            return UserDefaults.standard.string(forKey: key)
        }
        return UserDefaults.standard.string(forKey: globalKey)
    }

    final func bind(toShortcut index: Int) {
        currentShortcutIndex = index
        render()
    }

    final func write(_ value: String) {
        Preferences.set(key, value)
        onChange?()
    }

    /// Show `effectiveValue`.
    func render() {}
}

/// An index-valued look override (style, size, theme, after-keys-released).
class ShortcutOverrideIndexBinding: ShortcutOverrideBinding {
    let cases: [MacroPreference]
    /// The index on screen, so a click on it is recognized as no change.
    private(set) var shownIndex = 0

    init(baseName: String, cases: [MacroPreference], onChange: (() -> Void)?) {
        self.cases = cases
        super.init(baseName: baseName, onChange: onChange)
    }

    override final func render() {
        let index = Int(effectiveValue ?? "") ?? 0
        shownIndex = max(0, min(index, cases.count - 1))
        show(shownIndex)
    }

    final func chose(_ index: Int) {
        guard index != shownIndex else { return }
        shownIndex = index
        write(String(index))
    }

    func show(_ index: Int) {}
}

final class ShortcutOverrideSegmented: ShortcutOverrideIndexBinding {
    let segmented: NSSegmentedControl

    override init(baseName: String, cases: [MacroPreference], onChange: (() -> Void)?) {
        segmented = LabelAndControl.makeSegmentedControl(Preferences.indexToName(baseName, 0), cases, extraAction: nil)
        super.init(baseName: baseName, cases: cases, onChange: onChange)
        segmented.onAction = { [weak self] control in
            self?.chose((control as! NSSegmentedControl).selectedSegment)
        }
    }

    override func show(_ index: Int) {
        segmented.selectedSegment = index
    }
}

final class ShortcutOverrideDropdown: ShortcutOverrideIndexBinding {
    let popUp: PopupButtonLikeSystemSettings

    override init(baseName: String, cases: [MacroPreference], onChange: (() -> Void)?) {
        popUp = PopupButtonLikeSystemSettings(frame: .zero, pullsDown: false)
        popUp.addItems(withTitles: cases.map { $0.localizedString })
        super.init(baseName: baseName, cases: cases, onChange: onChange)
        popUp.onAction = { [weak self] control in
            self?.chose((control as! NSPopUpButton).indexOfSelectedItem)
        }
    }

    override func show(_ index: Int) {
        popUp.selectItem(at: index)
    }
}

/// The style picture cards.
final class ShortcutOverrideRadios: ShortcutOverrideIndexBinding {
    let stack: NSStackView

    override init(baseName: String, cases: [MacroPreference], onChange: (() -> Void)?) {
        stack = LabelAndControl.makeImageRadioButtons(
            Preferences.indexToName(baseName, 0),
            cases as! [ImageMacroPreference],
            extraAction: nil,
            buttonSpacing: 10)
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.radioGroup)
        stack.setAccessibilityLabel(NSLocalizedString("Style", comment: ""))
        super.init(baseName: baseName, cases: cases, onChange: onChange)
        for (i, buttonView) in buttonViews.enumerated() {
            buttonView.button.setAccessibilityLabel(buttonView.label.stringValue)
            buttonView.onClick = { [weak self] _ in
                self?.chose(i)
                self?.show(i)
            }
        }
    }

    private var buttonViews: [ImageTextButtonView] {
        stack.arrangedSubviews.compactMap { $0 as? ImageTextButtonView }
    }

    override func show(_ index: Int) {
        buttonViews.enumerated().forEach { $1.state = $0 == index ? .on : .off }
    }
}

/// "Preview the selected window" for one shortcut.
final class ShortcutOverrideSwitch: ShortcutOverrideBinding {
    let toggle: Switch

    override init(baseName: String, onChange: (() -> Void)?) {
        toggle = Switch(false)
        super.init(baseName: baseName, onChange: onChange)
        toggle.onAction = { [weak self] control in
            self?.write((control as? NSButton)?.state == .on ? "true" : "false")
        }
    }

    override func render() {
        let isOn = Preferences.hasOverride(baseName, currentShortcutIndex) ? CachedUserDefaults.bool(key) : CachedUserDefaults.bool(globalKey)
        toggle.setSilently(isOn ? .on : .off)
    }
}
