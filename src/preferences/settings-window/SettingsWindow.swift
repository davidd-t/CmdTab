import Cocoa

private struct SettingsSectionDefinition {
    let id: String
    let title: String
    /// The one-line description under the page header's title. A closure because the Appearance
    /// description names the user's first shortcut, which can change while the window is open.
    let description: () -> String
    /// Deferred view builder so `addSection` can wrap construction in
    /// `SettingsSearchIndex.indexed { ... }` and harvest inline-registered search strings +
    /// highlight targets as the section's factories build their widgets. The closure is invoked
    /// exactly once, in `addSection`.
    let builder: () -> NSView
    /// Optional hook for sections whose searchable content includes sidebar rows that are rebuilt
    /// *after* the initial build. When set, `addSection` skips
    /// `SidebarListRow`s in the build-time walk — they'd otherwise be captured as base targets that
    /// go stale on the next rebuild — and this closure re-registers the current rows into the
    /// section's *dynamic* search content (at build time, and again after each rebuild via
    /// `refreshSectionSearchContent`). nil for sections with no such rows.
    let registerDynamicSearchContent: (() -> Void)?
    /// Runs each time the page is put on screen, to refresh content that depends on other pages.
    var willShow: (() -> Void)? = nil
}

private final class SettingsSection {
    let id: String
    let title: String
    /// The whole page: header followed by the section's content. Built once, then kept.
    let page: NSView
    let descriptionLabel: NSTextField
    let description: () -> String
    let search: SettingsSectionSearchContent
    /// Labels on this section's detail pages (see `SettingsSearchIndex.registerDetailStrings`).
    let detailStrings: [(strings: [String], destination: () -> (page: SettingsPage, title: String))]
    /// See `SettingsSectionDefinition.registerDynamicSearchContent`. Re-run inside a fresh indexed
    /// scope by `refreshSectionSearchContent` to refresh this section's dynamic search content.
    let registerDynamicSearchContent: (() -> Void)?
    let willShow: (() -> Void)?

    init(_ definition: SettingsSectionDefinition, _ page: NSView, _ descriptionLabel: NSTextField, _ search: SettingsSectionSearchContent,
         _ detailStrings: [(strings: [String], destination: () -> (page: SettingsPage, title: String))]) {
        id = definition.id
        title = definition.title
        description = definition.description
        registerDynamicSearchContent = definition.registerDynamicSearchContent
        willShow = definition.willShow
        self.page = page
        self.descriptionLabel = descriptionLabel
        self.search = search
        self.detailStrings = detailStrings
    }

    func setDynamicSearchContent(_ strings: [String], _ targets: [SettingsSearchHighlightTarget]) {
        search.setDynamic(strings: strings, targets: targets)
    }

    func refreshDescription() {
        let value = description()
        if descriptionLabel.stringValue != value {
            descriptionLabel.stringValue = value
        }
    }
}

private final class SettingsSidebarCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier(rawValue: "SettingsSidebarCell")
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { refreshStyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func setupView() {
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(titleLabel)
        // Standard `NSTableCellView` layout for an `NSTableView.style = .sourceList` sidebar:
        // a small leading inset, the colored section tile, a fixed gap, then the title label.
        // AppKit handles the selection highlight pill and the sidebar material/background.
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsWindow.sidebarItemContentInset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: SettingsWindow.sidebarTileSize),
            iconView.heightAnchor.constraint(equalToConstant: SettingsWindow.sidebarTileSize),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -SettingsWindow.sidebarItemContentInset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshStyle()
    }

    func configure(_ section: SettingsSection) {
        titleLabel.stringValue = section.title
        // The tile keeps its own colors, selected or not, like System Settings.
        iconView.image = SettingsWindow.sectionTile(section.id, size: SettingsWindow.sidebarTileSize)
        refreshStyle()
    }

    private func refreshStyle() {
        titleLabel.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
    }
}

private final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class SidebarTableView: NSTableView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

private extension NSToolbarItem.Identifier {
    static let settingsBack = NSToolbarItem.Identifier("SettingsBack")
    static let settingsForward = NSToolbarItem.Identifier("SettingsForward")
    static let settingsTitle = NSToolbarItem.Identifier("SettingsTitle")
}

class SettingsWindow: NSWindow {
    /// Width of each page's content column. Pages are centered in the content pane and never
    /// wider than this.
    static let contentWidth = CGFloat(600)
    static let sidebarWidth = max(215, makeQuitButton().intrinsicContentSize.width.rounded(.up) + 2 * sidebarHorizontalPadding)
    static let sidebarTileSize = CGFloat(22)
    static let pageHeaderTileSize = CGFloat(44)
    /// Minimum gap between the content column and the content pane's edges.
    private static let contentHorizontalPadding = CGFloat(28)
    private static let contentTopPadding = CGFloat(10)
    private static let contentBottomPadding = CGFloat(30)
    private static let pageHeaderSpacing = CGFloat(20)
    private static let pageTransitionDuration = 0.18
    private static let searchFlashDuration = 1.5
    private static let minWindowHeight = CGFloat(400)
    private static let defaultWindowSize = NSSize(width: 920, height: 640)
    static let sidebarHorizontalPadding = CGFloat(10)
    /// Padding inside the row's cell view between the cell's leading edge and the icon.
    /// `NSTableView.style = .sourceList` already inserts the cell content into its rounded
    /// highlight pill, so we only add a small visual breathing-room here.
    static let sidebarItemContentInset = CGFloat(4)
    private static let controlHighlightLayerName = "settingsSearchControlHighlight"
    private static let segmentedControlHighlightLayerName = "settingsSearchSegmentHighlight"
    private static let controlHighlightInset = CGFloat(1)
    private static let controlHighlightMinCornerRadius = CGFloat(4)
    private static let controlHighlightMaxCornerRadius = CGFloat(9)
    static var shared: SettingsWindow!

    override var canBecomeKey: Bool { SecondaryWindows.canBecomeKey }

    private let splitViewController = NSSplitViewController()
    private let sidebarContainer = NSView()
    private let contentContainer = NSView()
    private let searchField = NSSearchField(frame: .zero)
    private let sidebarScrollView = NSScrollView()
    private let sidebarTableView = SidebarTableView()
    private let rightScrollView = NSScrollView()
    private let pageDocumentView = SettingsFlippedView(frame: .zero)
    /// The centered column (≤ `contentWidth`) that holds the one page on screen.
    private let pageColumn = NSView()
    private let quitButton = SettingsWindow.makeQuitButton()
    private let backButton = SettingsWindow.makeNavigationButton(NSImage.goBackTemplateName, NSLocalizedString("Back", comment: ""), "[")
    private let forwardButton = SettingsWindow.makeNavigationButton(NSImage.goForwardTemplateName, NSLocalizedString("Forward", comment: ""), "]")
    private let pageTitleLabel = NSTextField(labelWithString: "")
    private var sections = [SettingsSection]()
    private var navigation = SettingsNavigation(start: .section("appearance"))
    /// Asked in turn for a `.shortcut` / `.exception` page; the first that builds it wins.
    private var detailPageProviders = [(SettingsPage) -> (title: String, view: NSView)?]()
    /// What is on screen.
    private var displayedPage: SettingsPage?
    private var currentPageView: NSView?
    /// The label a pending flash is shown on, cleared when it ends or another starts.
    private var flashedTarget: SettingsSearchHighlightTarget?
    private var isSyncingSidebarSelection = false

    convenience init() {
        self.init(contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
                  styleMask: [.titled, .miniaturizable, .closable, .resizable, .fullSizeContentView],
                  backing: .buffered, defer: false)
        minSize = NSSize(width: Self.sidebarWidth + Self.contentWidth + 2 * Self.contentHorizontalPadding, height: Self.minWindowHeight)
        setupWindow()
        setupView()
        // setFrameAutosaveNameSafely applies the persisted frame (dropping a corrupt one that would
        // otherwise abort the app) and returns whether a VALID saved frame existed — false on first
        // launch OR when the saved frame was corrupt, both of which should fall through to the default.
        let hasSavedFrame = setFrameAutosaveNameSafely("SettingsWindow")
        if !hasSavedFrame {
            // No saved frame → enforce the default size and center on the active screen. AppKit's
            // `init(contentRect:)` isn't load-bearing here because the unified toolbar can shift
            // the effective frame; setting `contentSize` explicitly is the safe path.
            setContentSize(Self.defaultWindowSize)
            center()
        }
        Self.shared = self
    }

    private func setupWindow() {
        delegate = self
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        // The toolbar holds back/forward and the page title, after the sidebar (System Settings layout).
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
        toolbarStyle = .unified
        titlebarSeparatorStyle = .none
        pageTitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        pageTitleLabel.lineBreakMode = .byTruncatingTail
        backButton.target = self
        backButton.action = #selector(goBackClicked)
        forwardButton.target = self
        forwardButton.action = #selector(goForwardClicked)
    }

    private func setupView() {
        setupSplitView()
        setupSidebar()
        setupContentPane()
        sectionDefinitions().forEach { addSection($0) }
        ShortcutsTab.registerDetailPages(in: self)
        registerDetailPages(ExceptionsTab.detailPage)
        refreshControlsFromSettings()
        // Publish each section's dynamic search content (its rebuilt-after-build sidebar rows) now
        // that the section objects exist. Uses `self` directly — `SettingsWindow.shared` isn't
        // assigned until `init` finishes, so ShortcutsTab's own refresh calls no-op until then.
        sections.forEach { refreshSectionSearchContent($0.id) }
        sidebarTableView.reloadData()
        applySearch("")
    }

    private func setupSplitView() {
        let sidebarVC = NSViewController()
        sidebarVC.view = sidebarContainer
        let contentVC = NSViewController()
        contentVC.view = contentContainer
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        let contentItem = NSSplitViewItem(viewController: contentVC)
        splitViewController.splitViewItems = [sidebarItem, contentItem]
        splitViewController.splitView.dividerStyle = .thin
        contentViewController = splitViewController
    }

    private func setupSidebar() {
        setupSearchField(sidebarContainer)
        setupQuitButton(sidebarContainer)
        setupSidebarTable(sidebarContainer)
        // Tab order is set by `keyViewOrder()`, not by nextKeyView links (see `moveKeyFocus`).
    }

    private func setupContentPane() {
        rightScrollView.drawsBackground = false
        rightScrollView.hasVerticalScroller = true
        rightScrollView.hasHorizontalScroller = false
        rightScrollView.scrollerStyle = .overlay
        rightScrollView.automaticallyAdjustsContentInsets = false
        rightScrollView.contentInsets = NSEdgeInsetsZero
        rightScrollView.scrollerInsets = NSEdgeInsetsZero
        rightScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(rightScrollView)
        pageDocumentView.translatesAutoresizingMaskIntoConstraints = false
        rightScrollView.documentView = pageDocumentView
        pageColumn.translatesAutoresizingMaskIntoConstraints = false
        pageDocumentView.addSubview(pageColumn)
        let preferredColumnWidth = pageColumn.widthAnchor.constraint(equalToConstant: Self.contentWidth)
        preferredColumnWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            // The scroll view starts below the toolbar, which holds back/forward and the page title.
            rightScrollView.topAnchor.constraint(equalTo: contentContainer.safeAreaLayoutGuide.topAnchor),
            rightScrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            rightScrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            rightScrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            pageDocumentView.widthAnchor.constraint(equalTo: rightScrollView.contentView.widthAnchor),
            pageColumn.topAnchor.constraint(equalTo: pageDocumentView.topAnchor, constant: Self.contentTopPadding),
            pageColumn.bottomAnchor.constraint(equalTo: pageDocumentView.bottomAnchor, constant: -Self.contentBottomPadding),
            pageColumn.centerXAnchor.constraint(equalTo: pageDocumentView.centerXAnchor),
            pageColumn.leadingAnchor.constraint(greaterThanOrEqualTo: pageDocumentView.leadingAnchor, constant: Self.contentHorizontalPadding),
            pageColumn.widthAnchor.constraint(lessThanOrEqualToConstant: Self.contentWidth),
            preferredColumnWidth,
        ])
    }

    private func setupSearchField(_ parent: NSView) {
        searchField.delegate = self
        searchField.applySearchStyle()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(searchField)
        NSLayoutConstraint.activate([
            // Below the traffic lights, which sit in the toolbar band.
            searchField.topAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.topAnchor, constant: 2),
            searchField.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: Self.sidebarHorizontalPadding),
            searchField.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -Self.sidebarHorizontalPadding),
        ])
    }

    private func setupSidebarTable(_ parent: NSView) {
        sidebarScrollView.drawsBackground = false
        sidebarScrollView.hasVerticalScroller = true
        sidebarScrollView.hasHorizontalScroller = false
        sidebarScrollView.scrollerStyle = .overlay
        sidebarTableView.headerView = nil
        sidebarTableView.intercellSpacing = NSSize(width: 0, height: 2)
        sidebarTableView.rowHeight = 30
        sidebarTableView.backgroundColor = .clear
        sidebarTableView.focusRingType = .none
        sidebarTableView.usesAlternatingRowBackgroundColors = false
        sidebarTableView.style = .sourceList
        sidebarTableView.delegate = self
        sidebarTableView.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "SettingsSidebarColumn"))
        column.resizingMask = .autoresizingMask
        sidebarTableView.addTableColumn(column)
        sidebarScrollView.documentView = sidebarTableView
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(sidebarScrollView)
        NSLayoutConstraint.activate([
            sidebarScrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            // The scroll view sits flush to the sidebar edges. The `.sourceList` selection style
            // adds its own ~10pt internal inset for the row highlight pill, so the pill ends up
            // aligned with the search field (which itself is inset by `sidebarHorizontalPadding`
            // = 10pt). Insetting the scroll view here would compound that and push the highlight
            // too far in.
            sidebarScrollView.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            sidebarScrollView.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            sidebarScrollView.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -20),
        ])
    }

    private func setupQuitButton(_ parent: NSView) {
        quitButton.toolTip = quitButton.title
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(quitButton)
        NSLayoutConstraint.activate([
            quitButton.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            quitButton.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -10),
            quitButton.widthAnchor.constraint(lessThanOrEqualTo: parent.widthAnchor, constant: -Self.sidebarHorizontalPadding * 2),
        ])
    }

    private static func makeQuitButton() -> NSButton {
        let button = NSButton(title: String(format: NSLocalizedString("Quit %@", comment: "%@ is CmdTab"), App.name), target: nil, action: #selector(NSApplication.terminate(_:)))
        button.bezelStyle = .rounded
        return button
    }

    private static func makeNavigationButton(_ imageName: NSImage.Name, _ label: String, _ key: String) -> NSButton {
        let image = NSImage(named: imageName) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.setAccessibilityLabel(label)
        button.toolTip = label
        button.keyEquivalent = key
        button.keyEquivalentModifierMask = .command
        button.isEnabled = false
        return button
    }

    // MARK: - Sections

    private func sectionDefinitions() -> [SettingsSectionDefinition] {
        [
            SettingsSectionDefinition(id: "appearance", title: NSLocalizedString("Appearance", comment: ""),
                                      description: { String(format: NSLocalizedString("How the switcher looks when you press %@.", comment: ""), SettingsWindow.firstShortcutDescription()) },
                                      builder: AppearanceTab.initTab, registerDynamicSearchContent: nil,
                                      willShow: AppearanceTab.refreshLookNote),
            SettingsSectionDefinition(id: "shortcuts", title: NSLocalizedString("Shortcuts", comment: ""),
                                      description: { NSLocalizedString("The keys that open the switcher, and what each one shows.", comment: "") },
                                      builder: ShortcutsTab.initTab, registerDynamicSearchContent: ShortcutsTab.registerListSearchContent),
            SettingsSectionDefinition(id: "general", title: NSLocalizedString("General", comment: ""),
                                      description: { NSLocalizedString("Startup, menu bar, and your settings file.", comment: "") },
                                      builder: GeneralTab.initTab, registerDynamicSearchContent: nil),
            SettingsSectionDefinition(id: "exceptions", title: NSLocalizedString("Exceptions", comment: ""),
                                      description: { NSLocalizedString("Apps CmdTab should hide, or where it should leave ⌘Tab alone.", comment: "") },
                                      builder: ExceptionsTab.initTab, registerDynamicSearchContent: ExceptionsTab.registerListSearchContent),
        ]
    }

    /// "⌘Tab" for the default first shortcut, otherwise its keys as shown in the Shortcuts list.
    private static func firstShortcutDescription() -> String {
        let hold = Preferences.shortcut(Preferences.indexToName("holdShortcut", 0))?.keyEquivalent ?? ""
        let next = Preferences.shortcut(Preferences.indexToName("nextWindowShortcut", 0))?.keyEquivalent ?? ""
        if next == "⇥" { return hold + "Tab" }
        return hold + next
    }

    private static func tileStyle(_ id: String) -> (symbol: Symbols, top: NSColor, bottom: NSColor) {
        func rgb(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        switch id {
        case "appearance": return (.paintpalette, rgb(0xff9f0a), rgb(0xff7a00))
        case "shortcuts": return (.command, rgb(0x7d7aff), rgb(0x5e5ce6))
        case "exceptions": return (.handRaised, rgb(0xff5a7a), rgb(0xff2d55))
        default: return (.gearshape, rgb(0xa0a0a8), rgb(0x7c7c84))
        }
    }

    /// The section's glyph (see `tileStyle`) in white on a rounded square filled with the section's color, like the
    /// icons in the System Settings sidebar.
    static func sectionTile(_ id: String, size: CGFloat) -> NSImage {
        sectionTile(id, size: size, symbol: nil)
    }

    /// The section's tile with another glyph (e.g. the trackpad, on the gesture's page).
    static func sectionTile(_ id: String, size: CGFloat, symbol: NSImage?) -> NSImage {
        let style = tileStyle(id)
        // Rendered large, then drawn scaled down, so the glyph stays crisp at any tile size.
        let glyph = symbol ?? NSImage.fromSymbol(style.symbol, pointSize: max(size, 32))
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let radius = rect.width * 0.22
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSGradient(starting: style.top, ending: style.bottom)?.draw(in: path, angle: -90)
            guard glyph.size.width > 0, glyph.size.height > 0 else { return true }
            let box = rect.width * 0.6
            let scale = min(box / glyph.size.width, box / glyph.size.height)
            let glyphSize = NSSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
            let glyphRect = NSRect(x: rect.midX - glyphSize.width / 2, y: rect.midY - glyphSize.height / 2,
                                   width: glyphSize.width, height: glyphSize.height)
            let white = NSImage(size: glyphSize, flipped: false) { glyphBounds in
                glyph.draw(in: glyphBounds)
                NSColor.white.set()
                glyphBounds.fill(using: .sourceAtop)
                return true
            }
            white.draw(in: glyphRect)
            return true
        }
        return image
    }

    /// The header every page opens with: a large tile (or keycaps, for shortcut pages), the page
    /// name, and a one-line description.
    static func makePageHeader(tile: NSImage?, keys: [String]?, title: String, description: String) -> NSView {
        makePageHeaderParts(tile: tile, keys: keys, title: title, description: description).view
    }

    private static func makePageHeaderParts(tile: NSImage?, keys: [String]?, title: String, description: String) -> (view: NSView, description: NSTextField) {
        var views = [NSView]()
        if let tile {
            let imageView = NSImageView(image: tile)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.fit(pageHeaderTileSize, pageHeaderTileSize)
            views.append(imageView)
        }
        if let keys, !keys.isEmpty {
            views.append(LabelAndControl.makeKeycaps(keys, height: pageHeaderTileSize, fontSize: 20))
        }
        // A `LightLabel` via `makeText`, so a search for the page name finds and highlights it.
        let titleLabel = TableGroupView.makeText(title)
        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.font = NSFont.systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.isSelectable = false
        descriptionLabel.preferredMaxLayoutWidth = contentWidth - pageHeaderTileSize - 14
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSStackView(views: [titleLabel, descriptionLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        views.append(text)
        let header = NSStackView(views: views)
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        header.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
        header.setAccessibilityElement(true)
        header.setAccessibilityRole(.group)
        header.setAccessibilityLabel(title)
        return (header, descriptionLabel)
    }

    private func addSection(_ definition: SettingsSectionDefinition) {
        // Wrap the page's view construction in an `indexed { ... }` scope so that every factory
        // call inside (`LabelAndControl.makeDropdown`, `TableGroupView.makeText`,
        // etc.) pushes its searchable strings and highlight targets into a per-section `Builder`.
        // The harvested results become the section's `searchableStrings` / `highlightTargets`
        // directly — no second-pass walk over the view tree. The page header is also built
        // here so its title registration is captured by the same indexed scope.
        let (built, builder) = SettingsSearchIndex.indexed { () -> (header: (view: NSView, description: NSTextField), view: NSView) in
            let header = Self.makePageHeaderParts(tile: Self.sectionTile(definition.id, size: Self.pageHeaderTileSize), keys: nil,
                                                  title: definition.title, description: definition.description())
            return (header, definition.builder())
        }
        let header = built.header.view
        let sectionView = built.view
        let page = NSStackView(views: [header, sectionView])
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = Self.pageHeaderSpacing
        page.translatesAutoresizingMaskIntoConstraints = false
        header.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        sectionView.widthAnchor.constraint(lessThanOrEqualTo: page.widthAnchor).isActive = true
        // Inline-registered strings/targets are the source of truth; `collectSearchContent` still
        // runs as a safety net to catch direct widget creation in tabs (NSTextField, NSButton
        // etc. created outside the LabelAndControl/TableGroupView factories) that hasn't been
        // migrated to inline registration yet. The walk's results get unioned in via `Set` below.
        // Sections that manage rebuilt-after-build sidebar rows (`registerDynamicSearchContent`)
        // skip those rows here and publish them as dynamic content instead — see that hook.
        let skipSidebarRows = definition.registerDynamicSearchContent != nil
        var walkedStrings = [String]()
        var highlightTargets = [SettingsSearchHighlightTarget]()
        collectSearchContent(sectionView, &walkedStrings, &highlightTargets, skipSidebarRows: skipSidebarRows)
        highlightTargets.append(contentsOf: builder.targets)
        // Page order (the factories register as they build), without repeats: search results
        // list a section's settings in the order they appear on its page.
        var seen = Set<String>()
        let searchableStrings = (builder.strings + walkedStrings).filter { seen.insert($0).inserted }
        let search = SettingsSectionSearchContent(strings: searchableStrings, targets: highlightTargets)
        sections.append(SettingsSection(definition, page, built.header.description, search, builder.detailStrings))
    }

    /// Re-publish a section's dynamic search content (its sidebar rows) into the index. A section's
    /// rows are rebuilt *outside* the build-time `indexed { }` scope (e.g. ShortcutsTab's
    /// `refreshShortcutRows` from the +/- buttons, a recorder edit, an input-source change, or the
    /// pro-lock observer), so the rows' own `registerSearchContent` no-ops there. This re-opens a
    /// scope, re-registers the *current* rows, and swaps them into the section wholesale — no stale
    /// targets for removed rows, and freshly-added rows become searchable. Re-applies the active
    /// query so rebuilt rows light up immediately. Called once per section at the end of
    /// `setupView`, then by the owning tab after every rebuild.
    func refreshSectionSearchContent(_ id: String) {
        guard let section = sections.first(where: { $0.id == id }),
              let register = section.registerDynamicSearchContent else { return }
        let (_, builder) = SettingsSearchIndex.indexed { register() }
        section.setDynamicSearchContent(builder.strings, builder.targets)
        if !SettingsSearch.isQueryEmpty(searchField.stringValue) {
            applySearch(searchField.stringValue)
        }
    }

    private func collectSearchContent(_ root: NSView,
                                      _ textValues: inout [String],
                                      _ highlightTargets: inout [SettingsSearchHighlightTarget],
                                      skipSidebarRows: Bool) {
        // Sections that rebuild their sidebar rows after construction publish those rows as dynamic
        // search content (see `refreshSectionSearchContent`). Skipping `SidebarListRow`s here keeps
        // targets for since-removed rows out of the section's fixed base — that staleness was the
        // "typing 'sho' no longer highlights Shortcut N" bug.
        if skipSidebarRows, root is SeparatelyIndexedView { return }
        if let textField = root as? NSTextField {
            let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
                if let target = SettingsSearchHighlight.highlightTarget(textField) {
                    highlightTargets.append(target)
                }
            }
        } else if let popUpButton = root as? NSPopUpButton {
            let value = popUpButton.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
            }
            popUpButton.itemTitles.forEach {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    textValues.append(value)
                }
            }
            if let target = SettingsWindow.highlightTarget(popUpButton) {
                highlightTargets.append(target)
            }
        } else if let button = root as? NSButton {
            let value = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
            }
        } else if let segmentedControl = root as? NSSegmentedControl {
            (0..<segmentedControl.segmentCount).forEach {
                let value = (segmentedControl.label(forSegment: $0) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    textValues.append(value)
                }
            }
            if let target = SettingsWindow.highlightTarget(segmentedControl) {
                highlightTargets.append(target)
            }
        } else if let infoButton = root as? ClickHoverImageView {
            SettingsWindow.searchStrings(infoButton).forEach {
                textValues.append($0)
            }
            if let target = SettingsWindow.highlightTarget(infoButton) {
                highlightTargets.append(target)
            }
        } else if let textView = root as? NSTextView {
            let value = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
            }
        }
        root.subviews.forEach { collectSearchContent($0, &textValues, &highlightTargets, skipSidebarRows: skipSidebarRows) }
    }

    static func highlightTarget(_ popUpButton: NSPopUpButton) -> SettingsSearchHighlightTarget? {
        controlHighlightTarget(popUpButton) {
            SettingsWindow.searchStrings(popUpButton)
        }
    }

    static func highlightTarget(_ segmentedControl: NSSegmentedControl) -> SettingsSearchHighlightTarget? {
        let segmentLabels = (0..<segmentedControl.segmentCount).map {
            SettingsWindow.trimmedText(segmentedControl.label(forSegment: $0) ?? "")
        }
        if segmentLabels.allSatisfy(\.isEmpty) { return nil }
        var matchingSegmentIndexes = [Int]()
        return SettingsSearchHighlightTarget({ query in
            matchingSegmentIndexes = []
            segmentLabels.enumerated().forEach { index, label in
                if !label.isEmpty, SettingsSearch.match(query, in: label) != nil {
                    matchingSegmentIndexes.append(index)
                    return
                }
            }
            if matchingSegmentIndexes.isEmpty { return [] }
            return [0..<1]
        }, { _ in
            SettingsWindow.applySegmentedControlHighlight(to: segmentedControl, segmentIndexes: matchingSegmentIndexes)
        }, {
            SettingsWindow.clearSegmentedControlHighlight(from: segmentedControl)
        })
    }

    static func highlightTarget(_ infoButton: ClickHoverImageView) -> SettingsSearchHighlightTarget? {
        controlHighlightTarget(infoButton) {
            SettingsWindow.searchStrings(infoButton)
        }
    }

    static func controlHighlightTarget(_ control: NSView, _ searchableStrings: @escaping () -> [String]) -> SettingsSearchHighlightTarget? {
        if searchableStrings().isEmpty { return nil }
        return SettingsSearchHighlightTarget({ query in
            searchableStrings().contains {
                SettingsSearch.match(query, in: $0) != nil
            }
        }, {
            SettingsWindow.applyControlHighlight(to: control)
        }, {
            SettingsWindow.clearControlHighlight(from: control)
        })
    }

    private static func clearControlHighlight(from view: NSView) {
        view.layer?.sublayers?.filter { $0.name == controlHighlightLayerName }.forEach { $0.removeFromSuperlayer() }
    }

    private static func clearSegmentedControlHighlight(from view: NSView) {
        view.layer?.sublayers?.filter { $0.name == segmentedControlHighlightLayerName }.forEach { $0.removeFromSuperlayer() }
    }

    private static func applySegmentedControlHighlight(to control: NSSegmentedControl, segmentIndexes: [Int]) {
        clearSegmentedControlHighlight(from: control)
        control.layoutSubtreeIfNeeded()
        guard !segmentIndexes.isEmpty else { return }
        control.wantsLayer = true
        let segmentRects = segmentedControlSegmentRects(control)
        segmentIndexes.forEach {
            guard segmentRects.indices.contains($0) else { return }
            // Inset only vertically. A horizontal inset visibly shrinks the highlight rect — for
            // adjacent segments it stops the yellow from reaching the segment boundary, leaving a
            // gray sliver between the highlight and the neighbour. Touching at the boundary looks
            // correct because the rounded corners curve inward at top/bottom anyway.
            let rect = segmentRects[$0].insetBy(dx: 0, dy: 1)
            guard rect.width > 0, rect.height > 0 else { return }
            let layer = noAnimation { CAShapeLayer() }
            layer.name = segmentedControlHighlightLayerName
            layer.fillColor = Appearance.searchMatchHighlightColor.cgColor
            let cornerRadius = min(max(rect.height * 0.3, 4), 7)
            layer.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            control.layer?.insertSublayer(layer, at: 0)
        }
    }

    private static func segmentedControlSegmentRects(_ control: NSSegmentedControl) -> [CGRect] {
        let segmentCount = control.segmentCount
        if segmentCount <= 0 { return [] }
        let widths = (0..<segmentCount).map { max(control.width(forSegment: $0), 0) }
        let explicitWidthTotal = widths.reduce(0) {
            $0 + ($1 > 0 ? $1 : 0)
        }
        let autoSegmentCount = widths.filter { $0 == 0 }.count
        let autoSegmentWidth = autoSegmentCount > 0 ? max(control.bounds.width - explicitWidthTotal, 0) / CGFloat(autoSegmentCount) : 0
        var currentX = control.bounds.minX
        return widths.enumerated().map { index, width in
            let resolvedWidth = width > 0 ? width : autoSegmentWidth
            let isLastSegment = index == segmentCount - 1
            let segmentWidth = isLastSegment ? max(control.bounds.maxX - currentX, 0) : resolvedWidth
            defer { currentX += segmentWidth }
            return CGRect(x: currentX, y: control.bounds.minY, width: segmentWidth, height: control.bounds.height)
        }
    }

    private static func applyControlHighlight(to view: NSView) {
        clearControlHighlight(from: view)
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        view.wantsLayer = true
        let layer = noAnimation { CAShapeLayer() }
        layer.name = controlHighlightLayerName
        layer.fillColor = Appearance.searchMatchHighlightColor.cgColor
        let rect = view.bounds.insetBy(dx: -controlHighlightInset, dy: -controlHighlightInset)
        let cornerRadius = min(max(rect.height * 0.35, controlHighlightMinCornerRadius), controlHighlightMaxCornerRadius)
        layer.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        view.layer?.insertSublayer(layer, at: 0)
    }

    private static func appendTrimmed(_ text: String, _ values: inout [String]) {
        let value = trimmedText(text)
        if !value.isEmpty {
            values.append(value)
        }
    }

    private static func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func searchStrings(_ popUpButton: NSPopUpButton) -> [String] {
        var values = [String]()
        appendTrimmed(popUpButton.title, &values)
        popUpButton.itemTitles.forEach {
            appendTrimmed($0, &values)
        }
        return Array(Set(values))
    }

    private static func searchStrings(_ infoButton: ClickHoverImageView) -> [String] {
        var values = [String]()
        infoButton.searchableStrings.forEach {
            appendTrimmed($0, &values)
        }
        return Array(Set(values))
    }

    private func refreshControlsFromSettings() {
        GeneralTab.refreshControlsFromPreferences()
    }

    // MARK: - Pages and navigation

    /// Shows `page` and adds it to the back/forward history. Ends an active search. Opening a
    /// shortcut or exception page with no registered provider (or one that declines it) does nothing.
    func open(_ page: SettingsPage) {
        var detail: (title: String, view: NSView)?
        switch page {
        case .search:
            return
        case .section(let id):
            guard sections.contains(where: { $0.id == id }) else { return }
        case .shortcut, .exception:
            guard let built = buildDetailPage(page) else { return }
            detail = built
        }
        endSearchIfNeeded()
        navigation.open(page)
        showCurrentPage(detail: detail)
    }

    func navigateToSection(_ sectionId: String) {
        open(.section(sectionId))
    }

    /// Section builders register how to build `.shortcut` / `.exception` pages. Detail pages are
    /// rebuilt each time they are opened. Providers are asked in order; a provider returns nil
    /// for pages it doesn't build.
    func registerDetailPages(_ provider: @escaping (SettingsPage) -> (title: String, view: NSView)?) {
        detailPageProviders.append(provider)
    }

    private func buildDetailPage(_ page: SettingsPage) -> (title: String, view: NSView)? {
        for provider in detailPageProviders {
            if let built = provider(page) { return built }
        }
        return nil
    }

    /// Drops pages that no longer exist (e.g. a removed shortcut) from the history, showing
    /// `fallback` if the current page is one of them.
    func removePages(where shouldRemove: (SettingsPage) -> Bool, fallback: SettingsPage) {
        navigation.removePages(where: shouldRemove, fallback: fallback)
        if let displayedPage, displayedPage != .search, shouldRemove(displayedPage) {
            self.displayedPage = nil
        }
        showCurrentPage()
    }

    @objc private func goBackClicked() {
        // While searching, Back just clears the search and returns to the page before it.
        if isSearching {
            searchField.stringValue = ""
            applySearch("")
            return
        }
        navigation.goBack()
        showCurrentPage()
    }

    @objc private func goForwardClicked() {
        endSearchIfNeeded()
        navigation.goForward()
        showCurrentPage()
    }

    private var isSearching: Bool { !SettingsSearch.isQueryEmpty(searchField.stringValue) }

    /// Clears the search field without showing a page; the caller shows the page it navigates to.
    private func endSearchIfNeeded() {
        guard isSearching else { return }
        searchField.stringValue = ""
        applySearch("", showPage: false)
    }

    private static func sectionId(for page: SettingsPage) -> String? {
        switch page {
        case .section(let id): return id
        case .shortcut: return "shortcuts"
        case .exception: return "exceptions"
        case .search: return nil
        }
    }

    /// Puts `navigation.current` on screen (fading it in), and syncs the title, the back/forward
    /// buttons and the sidebar selection. A page already on screen is left as is.
    /// The search page is rebuilt on every call, since its results follow the query.
    private func showCurrentPage(detail: (title: String, view: NSView)? = nil) {
        let page = navigation.current
        if page != displayedPage || page == .search || detail != nil {
            if let resolved = resolvePage(page, detail) {
                // Results replacing results (typing) appear at once; only a page change fades.
                let animated = !(page == .search && displayedPage == .search)
                displayedPage = page
                pageTitleLabel.stringValue = resolved.title
                title = resolved.title
                show(resolved.view, animated: animated)
            }
        }
        // While searching, Back clears the search (see `goBackClicked`).
        backButton.isEnabled = navigation.canGoBack || page == .search
        forwardButton.isEnabled = navigation.canGoForward
        syncSidebarSelection(Self.sectionId(for: page))
    }

    private func resolvePage(_ page: SettingsPage, _ detail: (title: String, view: NSView)?) -> (title: String, view: NSView)? {
        switch page {
        case .section(let id):
            guard let section = sections.first(where: { $0.id == id }) else { return nil }
            section.refreshDescription()
            section.willShow?()
            return (section.title, section.page)
        case .search:
            return (NSLocalizedString("Search", comment: ""), makeSearchResultsView(searchField.stringValue))
        case .shortcut, .exception:
            if let detail { return detail }
            return buildDetailPage(page)
        }
    }

    // MARK: - Search results

    /// Every searchable label, in sidebar then page order: each section's own labels (its page),
    /// then the labels on its detail pages.
    private func searchEntries() -> [SettingsSearchEntry] {
        sections.flatMap { section -> [SettingsSearchEntry] in
            let own = section.search.searchableStrings.map {
                SettingsSearchEntry(label: $0, pageTitle: section.title, page: .section(section.id), rowID: $0)
            }
            let details = section.detailStrings.flatMap { group -> [SettingsSearchEntry] in
                let destination = group.destination()
                return group.strings.map { SettingsSearchEntry(label: $0, pageTitle: destination.title, page: destination.page, rowID: $0) }
            }
            return own + details
        }
    }

    /// One row per matching setting (its label, and the page it is on, in gray); clicking a row
    /// opens that page and flashes the setting. No match shows a short message instead.
    private func makeSearchResultsView(_ query: String) -> NSView {
        let results = SettingsSearchResults.results(query, in: searchEntries())
        guard !results.isEmpty else { return makeNoResultsView(query) }
        let group = SettingsSearchIndex.unindexed { TableGroupView(heading: nil, width: Self.contentWidth) }
        results.forEach { entry in
            _ = SettingsSearchIndex.unindexed {
                group.addNavigationRow(title: entry.label, subtitle: entry.pageTitle, accessory: nil) { [weak self] in
                    self?.openSearchResult(entry, query: query)
                }
            }
        }
        let container = NSStackView(views: [group])
        container.orientation = .vertical
        container.alignment = .leading
        container.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)
        return container
    }

    private func openSearchResult(_ entry: SettingsSearchEntry, query: String) {
        open(entry.page)
        guard navigation.current == entry.page, let pageView = currentPageView else { return }
        pageDocumentView.layoutSubtreeIfNeeded()
        guard let found = Self.findSetting(entry.rowID, in: pageView) else { return }
        scrollIntoView(found.view)
        flash(found.target, query: query)
    }

    /// The first visible control or label on the page showing `label` (as its text, or as one of
    /// its pop-up options or segments), with the highlight that marks it.
    private static func findSetting(_ label: String, in root: NSView) -> (view: NSView, target: SettingsSearchHighlightTarget)? {
        if root.isHidden { return nil }
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var target: SettingsSearchHighlightTarget?
        if let lightLabel = root as? LightLabel, trimmed(lightLabel.stringValue) == label {
            target = SettingsSearchHighlight.highlightTarget(lightLabel)
        } else if let popUp = root as? NSPopUpButton {
            if popUp.itemTitles.contains(where: { trimmed($0) == label }) { target = highlightTarget(popUp) }
        } else if let segmented = root as? NSSegmentedControl {
            if (0..<segmented.segmentCount).contains(where: { trimmed(segmented.label(forSegment: $0) ?? "") == label }) {
                target = highlightTarget(segmented)
            }
        } else if let textField = root as? NSTextField, !textField.isEditable, trimmed(textField.stringValue) == label {
            target = SettingsSearchHighlight.highlightTarget(textField)
        } else if let button = root as? NSButton, trimmed(button.title) == label {
            target = controlHighlightTarget(button) { [label] }
        } else if let infoButton = root as? ClickHoverImageView, searchStrings(infoButton).contains(label) {
            target = highlightTarget(infoButton)
        }
        if let target { return (root, target) }
        for subview in root.subviews {
            if let found = findSetting(label, in: subview) { return found }
        }
        return nil
    }

    /// Scrolls the page so `view` sits in the middle of the visible area, when it isn't fully visible.
    private func scrollIntoView(_ view: NSView) {
        let rect = view.convert(view.bounds, to: pageDocumentView)
        let visible = rightScrollView.contentView.bounds
        guard rect.minY < visible.minY || rect.maxY > visible.maxY else { return }
        let maxY = max(pageDocumentView.frame.height - visible.height, 0)
        let y = min(max(rect.midY - visible.height / 2, 0), maxY)
        rightScrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        rightScrollView.reflectScrolledClipView(rightScrollView.contentView)
    }

    /// Briefly shows the search highlight on the setting the user picked from the results.
    private func flash(_ target: SettingsSearchHighlightTarget, query: String) {
        flashedTarget?.clear()
        flashedTarget = target
        // Text labels mark the matched letters; controls (a pop-up found by an option) are marked whole.
        target.updateHighlight(query)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.searchFlashDuration) { [weak self, weak target] in
            guard let self, let target, self.flashedTarget === target else { return }
            target.clear()
            self.flashedTarget = nil
        }
    }

    private func makeNoResultsView(_ query: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: String(format: NSLocalizedString("No settings match “%@”", comment: ""), query))
        // Plain text, not a Tab stop.
        label.isSelectable = false
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        let container = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 60),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    private func show(_ view: NSView, animated: Bool = true) {
        // Already on screen (e.g. the first search keystroke keeps the same section): no fade, no scroll.
        guard currentPageView !== view else { return }
        currentPageView?.removeFromSuperview()
        currentPageView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        pageColumn.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: pageColumn.topAnchor),
            view.leadingAnchor.constraint(equalTo: pageColumn.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: pageColumn.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: pageColumn.bottomAnchor),
        ])
        pageDocumentView.layoutSubtreeIfNeeded()
        rightScrollView.contentView.scroll(to: .zero)
        rightScrollView.reflectScrolledClipView(rightScrollView.contentView)
        guard animated, isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            view.alphaValue = 1
            return
        }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.pageTransitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        }
    }

    private func syncSidebarSelection(_ sectionId: String?) {
        isSyncingSidebarSelection = true
        defer { isSyncingSidebarSelection = false }
        guard let sectionId, let row = sections.firstIndex(where: { $0.id == sectionId }) else {
            sidebarTableView.deselectAll(nil)
            return
        }
        if sidebarTableView.selectedRow != row {
            sidebarTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    // MARK: - Keyboard navigation

    /// Tab order: search → sidebar → Back → Forward → the current page's controls → search.
    /// Computed when Tab is pressed, so it follows page changes and rows rebuilt inside a page.
    /// Views that can't take focus right now (disabled, hidden, toolbar buttons without Full
    /// Keyboard Access) are skipped.
    func keyViewOrder() -> [NSView] {
        var views: [NSView] = [searchField, sidebarTableView, backButton, forwardButton]
        if let currentPageView {
            Self.collectKeyViews(currentPageView, &views)
        }
        return views
    }

    private static func collectKeyViews(_ view: NSView, _ views: inout [NSView]) {
        if view.isHidden || view is NSScroller { return }
        if let textField = view as? NSTextField, !textField.isEditable, !textField.isSelectable { return }
        if let imageView = view as? NSImageView, !imageView.isEditable { return }
        // A control is one stop; its own subviews (e.g. a search field's buttons) are not.
        if view is NSControl || view is NSTextView {
            views.append(view)
            return
        }
        // Containers that accept first responder only to take focus on click (e.g.
        // `TableGroupSetView`, so clicking the background ends text editing) are not stops.
        // Navigation rows are stack views too, but they are real stops (Space/Return opens them).
        if view is NavigationRowView || (view.acceptsFirstResponder && !(view is NSStackView || view is NSClipView || view is NSScrollView)) {
            views.append(view)
        }
        view.subviews.forEach { collectKeyViews($0, &views) }
    }

    /// Moves focus to the next/previous view in `keyViewOrder()` that can take it. Returns false
    /// when `view` isn't part of the order (then AppKit's default handling applies).
    private func moveKeyFocus(from view: NSView?, forward: Bool) -> Bool {
        guard var current = view else { return false }
        // While a text field is edited, the first responder is its field editor.
        if let editor = current as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView {
            current = field
        }
        let order = keyViewOrder()
        guard let start = order.firstIndex(where: { current === $0 || current.isDescendant(of: $0) }) else { return false }
        for step in 1..<order.count + 1 {
            let candidate = order[((start + (forward ? step : -step)) % order.count + order.count) % order.count]
            if candidate.window === self, !candidate.isHiddenOrHasHiddenAncestor, candidate.canBecomeKeyView {
                makeFirstResponder(candidate)
                return true
            }
        }
        return false
    }

    override func selectKeyView(following view: NSView) {
        if !moveKeyFocus(from: view, forward: true) { super.selectKeyView(following: view) }
    }

    override func selectKeyView(preceding view: NSView) {
        if !moveKeyFocus(from: view, forward: false) { super.selectKeyView(preceding: view) }
    }

    override func selectNextKeyView(_ sender: Any?) {
        if !moveKeyFocus(from: firstResponder as? NSView, forward: true) { super.selectNextKeyView(sender) }
    }

    override func selectPreviousKeyView(_ sender: Any?) {
        if !moveKeyFocus(from: firstResponder as? NSView, forward: false) { super.selectPreviousKeyView(sender) }
    }

    /// Run `changes` while preserving the user's scroll position. If the change in document height
    /// pushes the scroll origin, we compensate so the visible region stays put. Used by
    /// `AppearanceTab.refreshLookNote` when showing or hiding its note so the user's view doesn't jump.
    func preserveScrollPosition(during changes: () -> Void) {
        pageDocumentView.layoutSubtreeIfNeeded()
        let oldHeight = pageDocumentView.frame.height
        let oldY = rightScrollView.contentView.bounds.origin.y
        changes()
        pageDocumentView.layoutSubtreeIfNeeded()
        let delta = pageDocumentView.frame.height - oldHeight
        if oldY > 0 && delta != 0 {
            rightScrollView.contentView.scroll(to: NSPoint(x: 0, y: max(oldY + delta, 0)))
            rightScrollView.reflectScrolledClipView(rightScrollView.contentView)
        }
    }

    // MARK: - Search

    /// Typing shows the results page in place of the current page; clearing the query returns to
    /// the page the user was on before searching. Search is not a back/forward history entry.
    private func applySearch(_ query: String, showPage: Bool = true) {
        Popover.shared.updateSearchContext(query) { query, text in
            SettingsSearch.match(query, in: text)?.ranges ?? []
        }
        if SettingsSearch.isQueryEmpty(query) {
            navigation.endSearch()
        } else {
            navigation.beginSearch()
        }
        if showPage {
            showCurrentPage()
        }
    }

    #if DEBUG
    /// Types `query` into the search field, for `renderPages`.
    func renderSearch(_ query: String) {
        searchField.stringValue = query
        applySearch(query)
    }
    #endif

    override func close() {
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}

extension SettingsWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Defer to the next runloop tick: tearing down view trees, removing observers,
        // and dropping the last strong ref to `self` while AppKit is still inside its own
        // close machinery causes objc_release crashes on re-entry.
        DispatchQueue.main.async { [weak self] in
            guard let self, SettingsWindow.shared === self else { return }
            AppearanceTab.cleanup()
            ShortcutsTab.cleanup()
            GeneralTab.cleanup()
            ExceptionsTab.cleanup()
            SettingsWindow.shared = nil
        }
    }
}

extension SettingsWindow: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .settingsBack, .settingsForward, .settingsTitle, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case .settingsBack:
            item.view = backButton
            item.label = backButton.toolTip ?? ""
            item.isNavigational = true
        case .settingsForward:
            item.view = forwardButton
            item.label = forwardButton.toolTip ?? ""
            item.isNavigational = true
        case .settingsTitle:
            item.view = pageTitleLabel
        default:
            return nil
        }
        return item
    }
}

extension SettingsWindow: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        applySearch(searchField.stringValue)
    }
}

extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        30
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = sections[row]
        let cell = tableView.makeView(withIdentifier: SettingsSidebarCellView.identifier, owner: self) as? SettingsSidebarCellView ?? {
            let view = SettingsSidebarCellView()
            view.identifier = SettingsSidebarCellView.identifier
            return view
        }()
        cell.configure(section)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSidebarSelection else { return }
        let row = sidebarTableView.selectedRow
        guard row >= 0, row < sections.count else { return }
        open(.section(sections[row].id))
    }
}

/// A view whose search content its section publishes itself (see `refreshSectionSearchContent`),
/// so the build-time walk skips it.
final class SeparatelyIndexedView: NSStackView {}
