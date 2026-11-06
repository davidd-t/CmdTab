import Cocoa

/// The Appearance page: the switcher's style, size and theme, how it behaves, which details it
/// shows, and its animations. Built once with the Settings window and kept.
class AppearanceTab: NSObject {
    // Shared with the per-shortcut look controls in `ShortcutEditor`.
    static let labelSize = NSLocalizedString("Size", comment: "")
    static let labelTheme = NSLocalizedString("Theme", comment: "")
    static let labelShortcutStyle = NSLocalizedString("After keys are released", comment: "")
    static let labelPreviewSelectedWindow = NSLocalizedString("Preview the selected window", comment: "")

    private static let lookNoteFont = TableGroupView.subtitleFont

    /// Details rows that apply only to some styles. They stay visible (the settings are global, and a
    /// shortcut with its own look may use another style); under another style their subtitle says
    /// where they apply.
    private static var styleDependentRows = [StyleDependentRow]()
    private struct StyleDependentRow {
        let row: TableGroupView.RowInfo
        let styles: [AppearanceStylePreference]
        /// Shown when the row applies to the current style; nil for no subtitle.
        let subtitle: String?
        let appliesTo: String
    }
    private static let appliesToThumbnails = NSLocalizedString("Applies to the Thumbnails style", comment: "")
    private static let appliesToThumbnailsAndTitles = NSLocalizedString("Applies to the Thumbnails and Titles styles", comment: "")
    private static weak var detailsGroup: TableGroupView?
    /// "⌘` uses its own look", under the first group. Hidden while every shortcut follows this page.
    private static weak var lookNote: NSStackView?

    static func initTab() -> NSView {
        let width = SettingsWindow.contentWidth
        let note = makeLookNote()
        let top = NSStackView(views: [makeStyleGroup(width), note])
        top.orientation = .vertical
        top.alignment = .leading
        top.spacing = 7
        let view = NSStackView(views: [top, makeSwitcherGroup(width), makeDetailsGroup(width), makeAnimationsGroup(width)])
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 22
        view.translatesAutoresizingMaskIntoConstraints = false
        refreshStyleDependentRows()
        refreshLookNote()
        return view
    }

    static func cleanup() {
        styleDependentRows.removeAll()
        detailsGroup = nil
        lookNote = nil
    }

    // MARK: - Groups

    private static func makeStyleGroup(_ width: CGFloat) -> TableGroupView {
        let group = TableGroupView(heading: nil, width: width)
        let cards = LabelAndControl.makeImageRadioButtons("appearanceStyle", AppearanceStylePreference.allCases, extraAction: { _ in
            refreshStyleDependentRows()
            globalLookChanged()
        }, buttonSpacing: 10)
        cards.arrangedSubviews.compactMap { $0 as? ImageTextButtonView }.forEach {
            $0.button.setAccessibilityLabel($0.label.stringValue)
        }
        cards.setAccessibilityElement(true)
        cards.setAccessibilityRole(.radioGroup)
        cards.setAccessibilityLabel(NSLocalizedString("Style", comment: ""))
        // The cards fill the row, like the picture cards in System Settings.
        cards.widthAnchor.constraint(equalToConstant: width - 2 * (TableGroupView.borderWidth + TableGroupView.rowHorizontalPadding)).isActive = true
        group.addRow(leftViews: [cards])
        group.addRow(leftText: labelSize, rightViews: [labeled(LabelAndControl.makeSegmentedControl("appearanceSize", AppearanceSizePreference.allCases, extraAction: { _ in globalLookChanged() }), labelSize)])
        group.addRow(leftText: labelTheme, rightViews: [labeled(LabelAndControl.makeSegmentedControl("appearanceTheme", AppearanceThemePreference.allCases, extraAction: { _ in globalLookChanged() }), labelTheme)])
        return group
    }

    private static func makeSwitcherGroup(_ width: CGFloat) -> TableGroupView {
        let group = TableGroupView(heading: NSLocalizedString("Switcher", comment: ""), width: width)
        group.addRow(leftText: labelShortcutStyle, rightViews: [labeled(LabelAndControl.makeDropdown("shortcutStyle", ShortcutStylePreference.allCases, extraAction: { _ in globalLookChanged() }), labelShortcutStyle)])
        group.addRow(leftText: labelPreviewSelectedWindow,
                     rightViews: [labeled(LabelAndControl.makeSwitch("previewFocusedWindow", extraAction: { _ in globalLookChanged() }), labelPreviewSelectedWindow)],
                     subText: NSLocalizedString("Shows the window full-size behind the switcher.", comment: ""))
        let showOn = NSLocalizedString("Show on", comment: "")
        group.addRow(leftText: showOn, rightViews: [labeled(LabelAndControl.makeDropdown("showOnScreen", ShowOnScreenPreference.allCases), showOn)])
        return group
    }

    private static func makeDetailsGroup(_ width: CGFloat) -> TableGroupView {
        let group = TableGroupView(heading: NSLocalizedString("Details", comment: ""), width: width)
        let showTitles = NSLocalizedString("Show titles", comment: "")
        group.addRow(leftText: showTitles, rightViews: [labeled(LabelAndControl.makeDropdown("showTitles", ShowTitlesPreference.allCases), showTitles)])
        let truncation = NSLocalizedString("Shorten long titles at the", comment: "")
        group.addRow(leftText: truncation, rightViews: [labeled(LabelAndControl.makeSegmentedControl("titleTruncation", TitleTruncationPreference.allCases), truncation)])
        // "Hide …" preferences, shown as switches that are on when the thing is visible. Each row is
        // added with its longest subtitle so it has a subtitle line; `refreshStyleDependentRows` sets it.
        func addStyleDependentRow(_ label: String, _ key: String, _ styles: [AppearanceStylePreference], subtitle: String?) {
            let appliesTo = styles.contains(.titles) ? appliesToThumbnailsAndTitles : appliesToThumbnails
            let row = group.addRow(leftText: label, rightViews: [labeled(LabelAndControl.makeSwitch(key, reversed: true), label)],
                                   subText: [subtitle ?? "", appliesTo].max { $0.count < $1.count })
            styleDependentRows.append(StyleDependentRow(row: row, styles: styles, subtitle: subtitle, appliesTo: appliesTo))
        }
        styleDependentRows = []
        addStyleDependentRow(NSLocalizedString("Status icons", comment: ""), "hideStatusIcons", [.thumbnails, .titles],
                             subtitle: NSLocalizedString("Shows when a window is minimized or fullscreen.", comment: ""))
        addStyleDependentRow(NSLocalizedString("Space number labels", comment: ""), "hideSpaceNumberLabels", [.thumbnails, .titles], subtitle: nil)
        addStyleDependentRow(NSLocalizedString("Colored circles on mouse hover", comment: ""), "hideColoredCircles", [.thumbnails], subtitle: nil)
        detailsGroup = group
        return group
    }

    private static func makeAnimationsGroup(_ width: CGFloat) -> TableGroupView {
        let group = TableGroupView(heading: NSLocalizedString("Animations", comment: ""), width: width)
        let delay = NSLocalizedString("Delay before the switcher appears", comment: "")
        // Same range and steps as before: 0–900 ms in 50 ms steps.
        let views = LabelAndControl.makeLabelWithSlider("", "windowDisplayDelay", 0, 900, 19, true, "ms", width: 170)
        let slider = labeled(views[1], delay)
        let value = views[2] as! NSTextField
        value.alignment = .right
        value.textColor = .secondaryLabelColor
        value.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        value.fit(56, value.fittingSize.height)
        group.addRow(leftText: delay, rightViews: [slider, value],
                     subText: NSLocalizedString("A short delay avoids a flash when you tap ⌘Tab quickly.", comment: ""))
        let fadeOut = NSLocalizedString("Fade out the switcher", comment: "")
        group.addRow(leftText: fadeOut, rightViews: [labeled(LabelAndControl.makeSwitch("fadeOutAnimation"), fadeOut)])
        let fadeIn = NSLocalizedString("Fade in the window preview", comment: "")
        group.addRow(leftText: fadeIn, rightViews: [labeled(LabelAndControl.makeSwitch("previewFadeInAnimation"), fadeIn)])
        return group
    }

    private static func labeled<T: NSView>(_ view: T, _ label: String) -> T {
        view.setAccessibilityLabel(label)
        return view
    }

    /// A global value of the five per-shortcut look settings changed: shortcuts that follow this page
    /// show the new value in their editor.
    private static func globalLookChanged() {
        refreshLookNote()
    }

    /// Status icons and Space number labels apply to Thumbnails and Titles; colored circles to
    /// Thumbnails only. Called when `appearanceStyle` changes, by any path.
    static func refreshStyleDependentRows() {
        guard let detailsGroup else { return }
        let style = Preferences.appearanceStyle
        let update = {
            styleDependentRows.forEach { detailsGroup.setSubtitle($0.row, $0.styles.contains(style) ? $0.subtitle : $0.appliesTo) }
        }
        if let window = SettingsWindow.shared {
            window.preserveScrollPosition(during: update)
        } else {
            update()
        }
    }

    // MARK: - Look note

    private static func makeLookNote() -> NSStackView {
        let note = NSStackView()
        note.orientation = .horizontal
        note.alignment = .firstBaseline
        note.spacing = 0
        note.edgeInsets = NSEdgeInsets(top: 0, left: TableGroupView.rowHorizontalPadding, bottom: 0, right: TableGroupView.rowHorizontalPadding)
        note.isHidden = true
        lookNote = note
        return note
    }

    /// Shows which shortcuts have their own look ("⌘` uses its own look"), each linking to its page,
    /// or hides the note when every shortcut follows this page. Called when the page is shown and
    /// when a shortcut's look changes.
    static func refreshLookNote() {
        guard let note = lookNote else { return }
        let stored = Preferences.all
        var indices = Array(0..<Preferences.shortcutCount)
        if Preferences.nextWindowGesture != .disabled { indices.append(Preferences.gestureIndex) }
        let own = indices.filter { !ShortcutLook.followsAppearance(stored: stored, index: $0) }
        let names = own.map { lookNoteName($0) }
        // Unchanged: keep the views (and keyboard focus on a link).
        let shown = note.arrangedSubviews.compactMap { $0 as? LookLinkButton }
        if shown.map(\.name) == names, shown.map(\.tag) == own, note.isHidden == own.isEmpty { return }
        let update = {
            note.arrangedSubviews.forEach { $0.removeFromSuperview() }
            note.isHidden = own.isEmpty
            for (n, index) in own.enumerated() {
                if n > 0 { note.addArrangedSubview(lookNoteText(n == own.count - 1 ? NSLocalizedString(" and ", comment: "") : ", ")) }
                note.addArrangedSubview(LookLinkButton(name: names[n], index: index, font: lookNoteFont))
            }
            if !own.isEmpty {
                note.addArrangedSubview(lookNoteText(own.count == 1
                    ? NSLocalizedString(" uses its own look", comment: "e.g. ⌘` uses its own look")
                    : NSLocalizedString(" use their own look", comment: "e.g. ⌘` and ⌥⇥ use their own look")))
            }
        }
        if let window = SettingsWindow.shared {
            window.preserveScrollPosition(during: update)
        } else {
            update()
        }
    }

    /// The shortcut's keys as the Shortcuts list names them (e.g. "⌘`"), or the gesture's name.
    private static func lookNoteName(_ index: Int) -> String {
        if index == Preferences.gestureIndex { return ShortcutNaming.gestureName }
        let inputs = ShortcutsTab.inputsForNaming()
        return index < inputs.count ? inputs[index].keys : ShortcutNaming.gestureName
    }

    private static func lookNoteText(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = lookNoteFont
        label.textColor = .secondaryLabelColor
        return label
    }
}

/// A link in the look note: opens that shortcut's page.
private final class LookLinkButton: NSButton {
    let name: String

    init(name: String, index: Int, font: NSFont) {
        self.name = name
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        attributedTitle = NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: NSColor.linkColor])
        tag = index
        target = self
        action = #selector(clicked)
        setAccessibilityLabel(String(format: NSLocalizedString("Open the %@ shortcut", comment: ""), name))
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// Exactly the title's size, so the link sits in the sentence without the button's padding.
    override var intrinsicContentSize: NSSize {
        let size = attributedTitle.size()
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    @objc private func clicked() {
        SettingsWindow.shared?.open(.shortcut(tag))
    }
}

class Popover: NSPopover {
    static let shared = Popover()
    private var hidingInitiated = true
    private var searchQuery = ""
    private var searchMatchRanges: ((String, String) -> [Range<Int>])?
    private var currentMessage = ""
    private weak var currentMessageLabel: NSTextField?
    private var appearanceObservation: NSKeyValueObservation?

    override init() {
        super.init()
        delegate = self
        contentViewController = NSViewController()
        behavior = .semitransient
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func hide() {
        performClose(nil)
    }

    func updateSearchContext(_ query: String, _ searchMatchRanges: @escaping (String, String) -> [Range<Int>]) {
        searchQuery = query
        self.searchMatchRanges = searchMatchRanges
        applySearchHighlightToCurrentMessage()
    }

    func show(event: NSEvent, positioningView: NSView, message: String, extraView: NSView? = nil) {
        if !hidingInitiated { return }
        hidingInitiated = false
        let view = NSView()
        let label = NSTextField(labelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.isEditable = false
        label.isSelectable = true
        label.font = NSFont.systemFont(ofSize: 12)
        let actualView: NSView = extraView == nil ? label : StackView([label, extraView!], .vertical)
        view.addSubview(actualView)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
            actualView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            actualView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            actualView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            actualView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
        ])
        currentMessage = message
        currentMessageLabel = label
        applySearchHighlightToCurrentMessage()
        contentViewController?.view = view
        // Convert the mouse location to the positioning view's coordinate system
        let locationInWindow = event.locationInWindow
        let locationInPositioningView = positioningView.convert(locationInWindow, from: nil)
        let rect = CGRect(origin: locationInPositioningView, size: .zero)
        appearanceObservation = positioningView.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] view, _ in
            self?.appearance = view.effectiveAppearance
        }
        show(relativeTo: rect, of: positioningView, preferredEdge: .minX)
    }

    private func applySearchHighlightToCurrentMessage() {
        guard let label = currentMessageLabel else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: label.font ?? NSFont.systemFont(ofSize: 12),
            .foregroundColor: label.textColor ?? NSColor.labelColor
        ]
        let attributed = NSMutableAttributedString(string: currentMessage, attributes: attributes)
        guard let searchMatchRanges, !currentMessage.isEmpty else {
            label.attributedStringValue = attributed
            return
        }
        let ranges = searchMatchRanges(searchQuery, currentMessage)
        guard !ranges.isEmpty else {
            label.attributedStringValue = attributed
            return
        }
        SettingsSearchHighlight.applyInlineHighlight(to: attributed, ranges: ranges, in: currentMessage)
        label.attributedStringValue = attributed
    }
}

extension Popover: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        appearanceObservation = nil
        hidingInitiated = true
        currentMessage = ""
        currentMessageLabel = nil
    }
}

