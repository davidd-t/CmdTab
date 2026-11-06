import Cocoa

/// A custom view that organizes an array of views into a vertical stack to show the system like UI,
/// with specific handling for `TableGroupView` and other view types.
class TableGroupSetView: NSStackView {
    override var acceptsFirstResponder: Bool { true }
    static let spacing = CGFloat(20)
    static let tableGroupSpacing = CGFloat(5)
    static let othersSpacing = CGFloat(10)
    static let titleTableGroupSpacing = CGFloat(20)
    static let padding = CGFloat(20)
    static let leftRightPadding = 2 * TableGroupSetView.padding

    var verticalViews = [NSView]()
    var originalViews = [NSView]()

    convenience init(originalViews: [NSView],
                     toolsViews: [NSView]? = nil,
                     spacing: CGFloat = TableGroupSetView.spacing,
                     tableGroupSpacing: CGFloat = TableGroupSetView.tableGroupSpacing,
                     titleTableGroupSpacing: CGFloat = TableGroupSetView.titleTableGroupSpacing,
                     othersSpacing: CGFloat = TableGroupSetView.othersSpacing,
                     padding: CGFloat = TableGroupSetView.padding,
                     topPadding: CGFloat? = nil,
                     bottomPadding: CGFloat? = nil,
                     othersAlignment: NSLayoutConstraint.Attribute = .trailing,
                     toolsAlignment: NSLayoutConstraint.Attribute = .centerX) {
        self.init(frame: .zero)
        let resolvedTopPadding = topPadding ?? padding
        let resolvedBottomPadding = bottomPadding ?? padding
        self.spacing = spacing
        orientation = .vertical
        self.originalViews = originalViews
        var continuousTableGroups = [NSView]()
        var continuousOthers = [NSView]()
        var lastViewWasTableGroup = false
        // Consecutive views of the same kind share one wrapping stack. Each of these closes the run it
        // owns and is a no-op on an empty run, so they can be called at every boundary unconditionally.
        func flushTableGroups() {
            addContinuousTableGroupsToSetViews(&continuousTableGroups,
                                               views: &verticalViews,
                                               tableGroupSpacing: tableGroupSpacing,
                                               titleTableGroupSpacing: titleTableGroupSpacing,
                                               horizontalPadding: padding,
                                               topPadding: resolvedTopPadding)
        }
        func flushOthers() {
            addContinuousOthersToSetViews(&continuousOthers,
                                          views: &verticalViews,
                                          othersSpacing: othersSpacing,
                                          horizontalPadding: padding,
                                          topPadding: resolvedTopPadding,
                                          alignment: othersAlignment)
        }
        func addTools(_ views: [NSView]) {
            addToolsViewToSetViews(views, views: &verticalViews, horizontalPadding: padding, topPadding: resolvedTopPadding, alignment: toolsAlignment)
        }
        for view in originalViews {
            if view is TableGroupView {
                if !lastViewWasTableGroup { flushOthers() }
                continuousTableGroups.append(view)
                lastViewWasTableGroup = true
            } else {
                if lastViewWasTableGroup { flushTableGroups() }
                continuousOthers.append(view)
                lastViewWasTableGroup = false
            }
        }
        flushTableGroups()
        flushOthers()
        if let toolsViews {
            addTools(toolsViews)
        }
        if let lastStackView = verticalViews.last {
            lastStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -resolvedBottomPadding).isActive = true
        }
    }

    func addContinuousTableGroupsToSetViews(_ continuousTableGroups: inout [NSView],
                                            views: inout [NSView],
                                            tableGroupSpacing: CGFloat,
                                            titleTableGroupSpacing: CGFloat,
                                            horizontalPadding: CGFloat,
                                            topPadding: CGFloat) {
        if !continuousTableGroups.isEmpty {
            let stackView = NSStackView()
            stackView.orientation = .vertical
            stackView.spacing = tableGroupSpacing
            stackView.alignment = .leading
            continuousTableGroups.enumerated().forEach { (index, view) in
                if let tableGroupView = view as? TableGroupView, tableGroupView.title != nil {
                    var spacerHeight = CGFloat(0)
                    if index == 0 && !views.isEmpty {
                        // at first, height: spacing + padding
                        spacerHeight = titleTableGroupSpacing - spacing
                    } else if index > 0 {
                        // inner, height: tableGroupSpacing + padding
                        spacerHeight = titleTableGroupSpacing
                    }
                    let spacerView = NSView()
                    spacerView.translatesAutoresizingMaskIntoConstraints = false
                    spacerView.heightAnchor.constraint(equalToConstant: spacerHeight).isActive = true
                    stackView.addArrangedSubview(spacerView)
                    stackView.setCustomSpacing(0, after: spacerView)
                }
                stackView.addArrangedSubview(view)
                stackView.setCustomSpacing(0, after: view)
            }
            continuousTableGroups.removeAll()
            addArrangedSubview(stackView)
            setStackViewConstraints(stackView, isFirst: views.isEmpty, horizontalPadding: horizontalPadding, topPadding: topPadding)
            views.append(stackView)
        }
    }

    func addContinuousOthersToSetViews(_ continuousOthers: inout [NSView],
                                       views: inout [NSView],
                                       othersSpacing: CGFloat,
                                       horizontalPadding: CGFloat,
                                       topPadding: CGFloat,
                                       alignment: NSLayoutConstraint.Attribute) {
        if !continuousOthers.isEmpty {
            let stackView = NSStackView()
            stackView.orientation = .horizontal
            stackView.spacing = othersSpacing
            stackView.alignment = alignment
            stackView.setViews(continuousOthers, in: .leading)
            continuousOthers.removeAll()
            addArrangedSubview(stackView)
            setStackViewConstraints(stackView, isFirst: views.isEmpty, horizontalPadding: horizontalPadding, topPadding: topPadding)
            views.append(stackView)
        }
    }

    func addToolsViewToSetViews(_ originalViews: [NSView],
                                views: inout [NSView],
                                horizontalPadding: CGFloat,
                                topPadding: CGFloat,
                                alignment: NSLayoutConstraint.Attribute) {
        if !originalViews.isEmpty {
            let stackView = NSStackView()
            stackView.orientation = .horizontal
            stackView.spacing = TableGroupSetView.othersSpacing
            stackView.alignment = alignment
            stackView.setViews(originalViews, in: .leading)
            addArrangedSubview(stackView)
            setStackViewConstraints(stackView, isFirst: views.isEmpty, horizontalPadding: horizontalPadding, topPadding: topPadding)
            views.append(stackView)
        }
    }

    func setStackViewConstraints(_ stackView: NSStackView, isFirst: Bool, horizontalPadding: CGFloat, topPadding: CGFloat) {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        if isFirst {
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: topPadding).isActive = true
        }
        stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding).isActive = true
        stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding).isActive = true
    }
}

/// A custom component view that organizes titles and rows in a stack view format,
/// likes system settings UI, with configurable styles and events.
class TableGroupView: ClickHoverStackView {
    static let spacing = CGFloat(10)
    static let padding = CGFloat(10)
    static let rowIntraSpacing = CGFloat(5)
    static let cornerRadius = CGFloat(5)
    static let borderWidth = CGFloat(1)
    /// The rounded group, as in System Settings: 10pt corners, a hairline border, rows inset 12pt.
    static let cardCornerRadius = CGFloat(10)
    static let rowHorizontalPadding = CGFloat(12)
    static let rowVerticalPadding = CGFloat(7)
    static let rowMinHeight = CGFloat(40)
    /// Gap between a row's label column and its controls.
    static let rowColumnGap = CGFloat(16)
    static let headingSpacing = CGFloat(7)
    static let headingInset = CGFloat(4)
    static let subtitleFont = NSFont.systemFont(ofSize: 11.5)
    static let navigationIconSize = CGFloat(28)

    /// Group colors are translucent over the window background, so they sit "one step off" it in
    /// either appearance. Dynamic: AppKit re-resolves them per appearance when the NSBox draws.
    static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
    static let groupFillColor = dynamicColor(light: NSColor.black.withAlphaComponent(0.04), dark: NSColor.white.withAlphaComponent(0.055))
    static let groupBorderColor = dynamicColor(light: NSColor.black.withAlphaComponent(0.07), dark: NSColor.white.withAlphaComponent(0.06))
    static let rowSeparatorColor = dynamicColor(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.08))
    static let rowHoverColor = dynamicColor(light: NSColor.black.withAlphaComponent(0.05), dark: NSColor.white.withAlphaComponent(0.07))

    /// The rounded group drawn behind a table's rows (and reused by other card-like containers).
    static func makeCard() -> NSBox {
        let card = NSBox()
        card.boxType = .custom
        card.titlePosition = .noTitle
        card.contentViewMargins = .zero
        card.cornerRadius = cardCornerRadius
        card.borderWidth = borderWidth
        card.borderColor = groupBorderColor
        card.fillColor = groupFillColor
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    var title: String?
    var subTitle: String?

    var width: CGFloat = 500
    let titleLabel = NSTextField(labelWithString: "")
    let subTitleLabel = NSTextField(labelWithString: "")
    let titleStackView = NSStackView()
    let headerStackView = NSStackView()
    var tableStackViews = [NSStackView]()

    private var rowInfoTables = [[RowInfo]]()

    struct Row {
        let leftTitle: String
        let subTitle: String?
        let rightViews: [NSView]

        init(leftTitle: String, subTitle: String? = nil, rightViews: [NSView]) {
            self.leftTitle = leftTitle
            self.subTitle = subTitle
            self.rightViews = rightViews
        }
    }

    /// The constraints that size a row around its main row, kept so a subtitle change can resize it.
    fileprivate struct MainRowLayout {
        let mainRow: NSStackView
        let height: NSLayoutConstraint
        let top: NSLayoutConstraint
        let bottom: NSLayoutConstraint?
    }

    class RowInfo {
        let view: NSView
        var previousSeparator: NSView?
        var nextSeparator: NSView?

        var leftViews: [NSView]?
        /// The gray line under the label, for rows added with a subtitle (see `setSubtitle`).
        var subtitleLabel: NSTextField?
        fileprivate var mainRowLayout: MainRowLayout?

        init(view: NSView, previousSeparator: NSView? = nil, nextSeparator: NSView? = nil) {
            self.view = view
            self.previousSeparator = previousSeparator
            self.nextSeparator = nextSeparator
        }
    }

    init(title: String? = nil, subTitle: String? = nil, hasHeader: Bool = false, width: CGFloat = 500) {
        self.width = width
        self.title = title
        self.subTitle = subTitle
        super.init(frame: .zero)
        setupView(hasHeader: hasHeader)
    }

    /// A group with a small heading above it (13pt semibold, as System Settings does).
    convenience init(heading: String?, width: CGFloat) {
        self.init(title: heading, width: width)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// Width available to a row's content: the group minus its border and the row's side padding.
    private var rowContentWidth: CGFloat {
        width - 2 * (TableGroupView.borderWidth + TableGroupView.rowHorizontalPadding)
    }

    private func setupView(hasHeader: Bool) {
        orientation = .vertical
        spacing = TableGroupView.spacing
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        wantsLayer = true
        setupTitleView()
        if hasHeader {
            setupHeaderView()
        }
        addNewTable()
    }

    private func setupTitleView() {
        if title == nil && subTitle == nil { return }
        titleStackView.orientation = .vertical
        titleStackView.alignment = .leading
        titleStackView.spacing = TableGroupView.rowIntraSpacing
        let inset = TableGroupView.headingInset
        if let title {
            titleLabel.stringValue = title
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleLabel.alignment = .natural
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.maximumNumberOfLines = 0
            titleStackView.addArrangedSubview(titleLabel)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.leadingAnchor.constraint(equalTo: titleStackView.leadingAnchor, constant: inset).isActive = true
            titleLabel.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor, constant: -inset).isActive = true
            // Ensure height adjusts to content by setting priorities
            titleLabel.setContentHuggingPriority(.required, for: .vertical)
            titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        } else {
            titleLabel.isHidden = true
        }
        if let subTitle {
            subTitleLabel.stringValue = subTitle
            subTitleLabel.font = NSFont.systemFont(ofSize: 12)
            subTitleLabel.textColor = .secondaryLabelColor
            subTitleLabel.alignment = .natural
            subTitleLabel.lineBreakMode = .byWordWrapping
            subTitleLabel.maximumNumberOfLines = 0
            titleStackView.addArrangedSubview(subTitleLabel)
            subTitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subTitleLabel.leadingAnchor.constraint(equalTo: titleStackView.leadingAnchor, constant: inset).isActive = true
            subTitleLabel.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor, constant: -inset).isActive = true
            // Ensure height adjusts to content by setting priorities
            subTitleLabel.setContentHuggingPriority(.required, for: .vertical)
            subTitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            // Calculate the fitting height for subLabel and activate the height constraint
            let subLabelHeight = calculateHeightForLabel(subTitleLabel, width: width - 2 * inset)
            subTitleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: subLabelHeight).isActive = true
        } else {
            subTitleLabel.isHidden = true
        }
        addArrangedSubview(titleStackView)
        setCustomSpacing(TableGroupView.headingSpacing, after: titleStackView)
        titleStackView.translatesAutoresizingMaskIntoConstraints = false
        titleStackView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        titleStackView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        titleStackView.topAnchor.constraint(equalTo: topAnchor).isActive = true
    }

    private func setupHeaderView() {
        headerStackView.orientation = .horizontal
        headerStackView.alignment = .centerX
        headerStackView.spacing = TableGroupView.spacing
        addArrangedSubview(headerStackView)
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        headerStackView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
    }

    @discardableResult
    func addNewTable() -> NSStackView {
        let tableStackView = NSStackView()
        tableStackView.orientation = .vertical
        tableStackView.spacing = 0
        tableStackView.translatesAutoresizingMaskIntoConstraints = false
        // The card is a background sibling (not the rows' container) so the rows stack keeps driving its size.
        // Rows sit inside the card's hairline border, so their hover fill never covers it.
        let card = TableGroupView.makeCard()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)
        container.addSubview(tableStackView)
        let inset = TableGroupView.borderWidth
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tableStackView.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            tableStackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            tableStackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            tableStackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
        addArrangedSubview(container)
        tableStackViews.append(tableStackView)
        rowInfoTables.append([RowInfo]())
        container.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        container.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        return tableStackView
    }

    @discardableResult
    func addRow(_ row: Row, onClick: EventClosure? = nil, onMouseEntered: EventClosure? = nil, onMouseExited: EventClosure? = nil) -> RowInfo {
        return addRow(leftText: row.leftTitle, rightViews: row.rightViews, subText: row.subTitle,
            onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
    }

    @discardableResult
    func addRow(leftText: String? = nil, rightViews: NSView, subText: String? = nil,
                onClick: EventClosure? = nil,
                onMouseEntered: EventClosure? = nil,
                onMouseExited: EventClosure? = nil) -> RowInfo {
        return addRow(leftText: leftText, rightViews: [rightViews], subText: subText,
            onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
    }

    /// A label (with an optional gray subtitle under it) on the left, controls on the right,
    /// vertically centered against the whole label block.
    @discardableResult
    func addRow(leftText: String? = nil, rightViews: [NSView]? = nil, subText: String? = nil,
                isAddSeparator: Bool = true,
                onClick: EventClosure? = nil,
                onMouseEntered: EventClosure? = nil,
                onMouseExited: EventClosure? = nil) -> RowInfo {
        let rowView = ClickHoverStackView()
        configureRowView(rowView)
        let titleLabel = TableGroupView.makeText(leftText)
        let block = makeLabelBlock(titleLabel, subText: subText, rightViews: rightViews ?? [], rightSpacing: TableGroupView.spacing)
        let mainRow = createMainRow(leftViews: [block.view], rightViews: rightViews)
        let layout = setMainRow(mainRow, in: rowView)
        let rowInfo = RowInfo(view: rowView)
        rowInfo.leftViews = [titleLabel]
        rowInfo.subtitleLabel = block.subtitle
        rowInfo.mainRowLayout = layout
        finalizeRow(rowInfo: rowInfo, rowView: rowView, isAddSeparator: isAddSeparator,
            onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
        rowInfoTables[rowInfoTables.count - 1].append(rowInfo)
        updateRowCornerRadius()
        return rowInfo
    }

    @discardableResult
    func addRow(leftViews: [NSView]? = nil, rightViews: [NSView]? = nil, secondaryViews: [NSView]? = nil,
                isAddSeparator: Bool = true,
                secondaryViewsOrientation: NSUserInterfaceLayoutOrientation = .horizontal,
                secondaryViewsAlignment: NSLayoutConstraint.Attribute = .leading,
                secondaryViewsTopGap: CGFloat = 2,
                onClick: EventClosure? = nil,
                onMouseEntered: EventClosure? = nil,
                onMouseExited: EventClosure? = nil) -> RowInfo {
        let rowView = ClickHoverStackView()
        configureRowView(rowView)
        let mainRow = createMainRow(leftViews: leftViews, rightViews: rightViews)
        if let secondaryViews {
            setMainRow(mainRow, in: rowView, hasSecondaryRow: true)
            setSecondaryRow(secondaryViews, rowView: rowView, mainRow: mainRow, orientation: secondaryViewsOrientation, alignment: secondaryViewsAlignment, topGap: secondaryViewsTopGap)
        } else {
            setMainRow(mainRow, in: rowView)
        }
        let rowInfo = RowInfo(view: rowView)
        rowInfo.leftViews = leftViews
        finalizeRow(rowInfo: rowInfo, rowView: rowView, isAddSeparator: isAddSeparator,
            onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
        rowInfoTables[rowInfoTables.count - 1].append(rowInfo)
        updateRowCornerRadius()
        return rowInfo
    }

    /// A row that opens a detail page: title (and optional subtitle) on the left, an optional
    /// accessory (e.g. keycaps or a value) and a chevron on the right. The whole row is the
    /// target: it highlights on hover, opens on click, takes keyboard focus (Space or Return
    /// opens it), and VoiceOver reads it as a button.
    @discardableResult
    func addNavigationRow(title: String, subtitle: String?, accessory: NSView?, icon: NSImage? = nil, onClick: @escaping () -> Void) -> RowInfo {
        let rowView = NavigationRowView()
        configureRowView(rowView)
        rowView.activate = onClick
        rowView.setAccessibilityLabel(title)
        if let subtitle { rowView.setAccessibilityHelp(subtitle) }
        let rightSpacing = CGFloat(12)
        let rightViews = (accessory.map { [$0] } ?? []) + [TableGroupView.makeChevron()]
        let titleLabel = TableGroupView.makeText(title)
        let block = makeLabelBlock(titleLabel, subText: subtitle, rightViews: rightViews, rightSpacing: rightSpacing)
        var leftViews = [block.view]
        if let icon {
            // An optional leading icon (e.g. an app's icon on the Exceptions list).
            let iconView = NSImageView(image: icon)
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.setAccessibilityElement(false)
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.widthAnchor.constraint(equalToConstant: TableGroupView.navigationIconSize).isActive = true
            iconView.heightAnchor.constraint(equalToConstant: TableGroupView.navigationIconSize).isActive = true
            leftViews.insert(iconView, at: 0)
        }
        let mainRow = createMainRow(leftViews: leftViews, rightViews: rightViews, rightSpacing: rightSpacing)
        let layout = setMainRow(mainRow, in: rowView)
        let rowInfo = RowInfo(view: rowView)
        rowInfo.leftViews = [titleLabel]
        rowInfo.subtitleLabel = block.subtitle
        rowInfo.mainRowLayout = layout
        finalizeRow(rowInfo: rowInfo, rowView: rowView, isAddSeparator: true,
            onClick: { _, _ in onClick() }, onMouseEntered: { _, _ in }, onMouseExited: nil)
        rowInfoTables[rowInfoTables.count - 1].append(rowInfo)
        updateRowCornerRadius()
        return rowInfo
    }

    static func makeChevron() -> NSView {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        let chevron = NSImageView()
        chevron.image = image
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.setAccessibilityElement(false)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        return chevron
    }

    /// Rows always go to the table opened last: `addNewTable` is what starts a new one.
    private func finalizeRow(rowInfo: RowInfo, rowView: ClickHoverStackView, isAddSeparator: Bool,
                             onClick: EventClosure?, onMouseEntered: EventClosure?, onMouseExited: EventClosure?) {
        rowInfo.previousSeparator = addSeparatorIfNeeded(isAddSeparator: isAddSeparator)
        if let tableStackView = tableStackViews.last {
            tableStackView.addArrangedSubview(rowView)
            rowView.leadingAnchor.constraint(equalTo: tableStackView.leadingAnchor).isActive = true
            rowView.trailingAnchor.constraint(equalTo: tableStackView.trailingAnchor).isActive = true
        }
        setRowViewEvents(rowView, onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
    }

    private func configureRowView(_ rowView: ClickHoverStackView) {
        rowView.orientation = .vertical
        rowView.alignment = .leading
        rowView.spacing = TableGroupView.rowIntraSpacing
        rowView.wantsLayer = true
        // The hover highlight is an NSBox with a dynamic fillColor, so AppKit re-resolves its color
        // per appearance on its own; we only toggle its visibility on enter/exit. The row layer
        // clips it to the table's rounded corners (see updateRowCornerRadius).
        rowView.layer?.masksToBounds = true
        rowView.layer?.cornerCurve = .continuous
        let hover = NSBox()
        hover.boxType = .custom
        hover.titlePosition = .noTitle
        hover.borderWidth = 0
        hover.fillColor = TableGroupView.rowHoverColor
        hover.contentViewMargins = .zero
        hover.isHidden = true
        hover.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(hover, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            hover.topAnchor.constraint(equalTo: rowView.topAnchor),
            hover.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            hover.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            hover.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
        ])
        rowView.hoverBackground = hover
    }

    static func makeText(_ leftText: String?, bold: Bool = false) -> LightLabel {
        // Use `LightLabel` (custom NSView + `NSAttributedString.draw`) instead of `NSTextField`.
        // For static row titles, NSTextField pays a per-redraw cost on every key-state cascade
        // (NSCell setup, TextKit2 layout, the Tahoe SwiftUI-text bridge) that LightLabel avoids.
        // Same visible behavior; substantially cheaper at scale (hundreds of labels per window).
        let leftLabel = LightLabel(leftText ?? "")
        if bold {
            leftLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        }
        leftLabel.alignment = .left
        leftLabel.lineBreakMode = .byTruncatingTail
        leftLabel.maximumNumberOfLines = 1
        SettingsSearchIndex.registerString(leftText)
        SettingsSearchIndex.registerTarget(SettingsSearchHighlight.highlightTarget(leftLabel))
        return leftLabel
    }

    /// The row's label, with its subtitle (if any) stacked under it. The subtitle wraps within
    /// the room the controls on the right leave.
    private func makeLabelBlock(_ titleLabel: NSView, subText: String?, rightViews: [NSView], rightSpacing: CGFloat) -> (view: NSView, subtitle: NSTextField?) {
        guard let subText else { return (titleLabel, nil) }
        let rightWidth = rightViews.reduce(CGFloat(0)) { $0 + $1.fittingSize.width } + CGFloat(max(0, rightViews.count - 1)) * rightSpacing
        let available = max(120, rowContentWidth - rightWidth - (rightViews.isEmpty ? 0 : TableGroupView.rowColumnGap))
        let subLabel = createSubLabel(with: subText, width: available)
        let block = NSStackView(views: [titleLabel, subLabel])
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 1
        return (block, subLabel)
    }

    private func createMainRow(leftViews: [NSView]?, rightViews: [NSView]?, rightSpacing: CGFloat = TableGroupView.spacing) -> NSStackView {
        let mainRow = NSStackView()
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.spacing = 0
        let spacer = NSView() // Spacer to fill the middle space
        let leftStackView = NSStackView()
        leftStackView.orientation = .horizontal
        // Centered, not left to chance: the stack can come out as tall as the row's controls, and then a label
        // with no vertical alignment sat at its top, a few points above the control beside it.
        leftStackView.alignment = .centerY
        leftStackView.spacing = TableGroupView.spacing
        if let leftViews {
            leftStackView.setViews(leftViews, in: .leading)
        }
        let rightStackView = NSStackView()
        rightStackView.orientation = .horizontal
        rightStackView.alignment = .centerY
        rightStackView.spacing = rightSpacing
        if let rightViews {
            rightStackView.setViews(rightViews, in: .leading)
        }
        mainRow.addArrangedSubview(leftStackView)
        mainRow.addArrangedSubview(spacer)
        mainRow.addArrangedSubview(rightStackView)
        leftStackView.translatesAutoresizingMaskIntoConstraints = false
        rightStackView.translatesAutoresizingMaskIntoConstraints = false
        spacer.translatesAutoresizingMaskIntoConstraints = false
        leftStackView.leadingAnchor.constraint(equalTo: mainRow.leadingAnchor).isActive = true
        rightStackView.trailingAnchor.constraint(equalTo: mainRow.trailingAnchor).isActive = true
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        let gap = spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: TableGroupView.rowColumnGap)
        gap.priority = .defaultHigh
        gap.isActive = true
        return mainRow
    }

    /// The main row keeps its natural height; without a secondary row it is centered in a row of
    /// at least `rowMinHeight`.
    @discardableResult
    private func setMainRow(_ mainRow: NSStackView, in rowView: ClickHoverStackView, hasSecondaryRow: Bool = false) -> MainRowLayout {
        rowView.addArrangedSubview(mainRow)
        mainRow.translatesAutoresizingMaskIntoConstraints = false
        let height = mainRow.fittingSize.height
        let verticalPadding = hasSecondaryRow ? TableGroupView.rowVerticalPadding : Self.verticalPadding(height)
        let top = mainRow.topAnchor.constraint(equalTo: rowView.topAnchor, constant: verticalPadding)
        let heightConstraint = mainRow.heightAnchor.constraint(equalToConstant: height)
        let bottom = hasSecondaryRow ? nil : mainRow.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -verticalPadding)
        NSLayoutConstraint.activate([
            top, heightConstraint,
            mainRow.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: TableGroupView.rowHorizontalPadding),
            mainRow.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -TableGroupView.rowHorizontalPadding),
        ] + (bottom.map { [$0] } ?? []))
        return MainRowLayout(mainRow: mainRow, height: heightConstraint, top: top, bottom: bottom)
    }

    /// Centers a main row of `height` in a row of at least `rowMinHeight`.
    private static func verticalPadding(_ height: CGFloat) -> CGFloat {
        max(TableGroupView.rowVerticalPadding, ((TableGroupView.rowMinHeight - height) / 2).rounded(.up))
    }

    /// Changes a row's subtitle; nil hides it. Only for rows added with `addRow(leftText:…subText:)`
    /// and a subtitle. The row grows or shrinks to fit.
    func setSubtitle(_ rowInfo: RowInfo, _ text: String?) {
        guard let label = rowInfo.subtitleLabel, let layout = rowInfo.mainRowLayout else { return }
        guard label.isHidden != (text == nil) || label.stringValue != (text ?? label.stringValue) else { return }
        if let text { label.stringValue = text }
        label.isHidden = text == nil
        let labelHeight = calculateHeightForLabel(label, width: label.preferredMaxLayoutWidth)
        label.constraints.filter { $0.firstAttribute == .height && $0.relation == .greaterThanOrEqual }.forEach { $0.constant = labelHeight }
        layout.height.isActive = false
        let height = layout.mainRow.fittingSize.height
        layout.height.constant = height
        layout.height.isActive = true
        let padding = Self.verticalPadding(height)
        layout.top.constant = padding
        layout.bottom?.constant = -padding
    }

    private func createSubLabel(with text: String, width: CGFloat) -> NSTextField {
        let subLabel = NSTextField(wrappingLabelWithString: text)
        subLabel.font = TableGroupView.subtitleFont
        subLabel.textColor = .secondaryLabelColor
        subLabel.isSelectable = false
        subLabel.alignment = .left
        subLabel.lineBreakMode = .byWordWrapping
        subLabel.maximumNumberOfLines = 0
        subLabel.preferredMaxLayoutWidth = width
        subLabel.setContentHuggingPriority(.required, for: .vertical)
        subLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        subLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        let subLabelHeight = calculateHeightForLabel(subLabel, width: width)
        subLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: subLabelHeight).isActive = true
        return subLabel
    }

    private func setSecondaryRow(_ secondaryRows: [NSView]?, rowView: ClickHoverStackView, mainRow: NSStackView,
                                 orientation: NSUserInterfaceLayoutOrientation = .horizontal,
                                 alignment: NSLayoutConstraint.Attribute = .leading,
                                 topGap: CGFloat = 2) {
        let secondaryRow = NSStackView()
        secondaryRow.orientation = orientation
        secondaryRow.alignment = alignment
        secondaryRow.spacing = TableGroupView.rowIntraSpacing
        if let secondaryRows {
            secondaryRow.setViews(secondaryRows, in: .leading)
        }
        rowView.addSubview(secondaryRow)
        let padding = TableGroupView.rowHorizontalPadding
        secondaryRow.translatesAutoresizingMaskIntoConstraints = false
        secondaryRow.topAnchor.constraint(equalTo: mainRow.bottomAnchor, constant: topGap).isActive = true
        secondaryRow.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -TableGroupView.rowVerticalPadding - 3).isActive = true
        // constrain trailing to the right views' leading so subtitle wraps before the toggle
        let rightStackView = mainRow.arrangedSubviews[2]
        switch alignment {
            case .leading:
                secondaryRow.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: padding).isActive = true
                secondaryRow.trailingAnchor.constraint(lessThanOrEqualTo: rightStackView.leadingAnchor).isActive = true
            case .centerX:
                secondaryRow.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: padding).isActive = true
                secondaryRow.trailingAnchor.constraint(equalTo: rightStackView.leadingAnchor).isActive = true
            case .right:
                secondaryRow.leadingAnchor.constraint(greaterThanOrEqualTo: rowView.leadingAnchor, constant: padding).isActive = true
                secondaryRow.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -padding).isActive = true
            default: break
        }
    }

    private func addSeparatorIfNeeded(isAddSeparator: Bool = true) -> NSView? {
        guard !rowInfoTables[rowInfoTables.count - 1].isEmpty else { return nil }
        guard isAddSeparator, let tableStackView = tableStackViews.last else { return nil }
        // A hairline inset on both sides, as System Settings draws between rows.
        let separator = NSBox()
        separator.boxType = .custom
        separator.titlePosition = .noTitle
        separator.borderWidth = 0
        separator.fillColor = TableGroupView.rowSeparatorColor
        separator.contentViewMargins = .zero
        separator.translatesAutoresizingMaskIntoConstraints = false
        tableStackView.addArrangedSubview(separator)
        separator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth).isActive = true
        separator.leadingAnchor.constraint(equalTo: tableStackView.leadingAnchor, constant: TableGroupView.rowHorizontalPadding).isActive = true
        separator.trailingAnchor.constraint(equalTo: tableStackView.trailingAnchor, constant: -TableGroupView.rowHorizontalPadding).isActive = true
        var lastTable = rowInfoTables[rowInfoTables.count - 1]
        if let lastRow = lastTable.last {
            lastRow.nextSeparator = separator
            lastTable[lastTable.count - 1] = lastRow
        }
        return separator
    }

    private func setRowViewEvents(_ rowView: ClickHoverStackView,
                                  onClick: EventClosure?,
                                  onMouseEntered: EventClosure?,
                                  onMouseExited: EventClosure?) {
        rowView.onClick = { event, view in
            onClick?(event, view)
        }
        rowView.onMouseEntered = { [weak self] event, view in
            guard let self, let onMouseEntered else { return }
            self.rowInfoTables.forEach { table in
                if let rowInfo = table.first(where: { $0.view === view }) {
                    self.setHovered(rowInfo, true)
                    onMouseEntered(event, view)
                }
            }
        }
        rowView.onMouseExited = { [weak self] event, view in
            guard let self else { return }
            self.rowInfoTables.forEach { table in
                if let rowInfo = table.first(where: { $0.view === view }) {
                    self.setHovered(rowInfo, false)
                    onMouseExited?(event, view)
                }
            }
        }
    }

    /// The hover fill covers the row's full width, so the separators touching it hide meanwhile.
    private func setHovered(_ rowInfo: RowInfo, _ hovered: Bool) {
        (rowInfo.view as? ClickHoverStackView)?.hoverBackground?.isHidden = !hovered
        rowInfo.previousSeparator?.alphaValue = hovered ? 0 : 1
        rowInfo.nextSeparator?.alphaValue = hovered ? 0 : 1
    }

    private func calculateHeightForLabel(_ label: NSTextField, width: CGFloat) -> CGFloat {
        let fittingSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let boundingRect = label.attributedStringValue.boundingRect(with: fittingSize, options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(boundingRect.height)
    }

    private func updateRowCornerRadius() {
        // Rows sit inside the card's border, so their corners follow its inner edge.
        let cornerRadius = TableGroupView.cardCornerRadius - TableGroupView.borderWidth
        rowInfoTables.forEach { table in
            for (index, rowInfo) in table.enumerated() {
                if table.count == 1 {
                    rowInfo.view.layer?.cornerRadius = cornerRadius
                    rowInfo.view.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner, .layerMinXMinYCorner, .layerMaxXMinYCorner]
                } else if index == 0 {
                    rowInfo.view.layer?.cornerRadius = cornerRadius
                    rowInfo.view.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                } else if index == table.count - 1 {
                    rowInfo.view.layer?.cornerRadius = cornerRadius
                    rowInfo.view.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                } else {
                    rowInfo.view.layer?.cornerRadius = 0
                    rowInfo.view.layer?.maskedCorners = []
                }
            }
        }
    }
}

/// A row that opens a detail page (see `TableGroupView.addNavigationRow`). It is a keyboard stop of
/// its own: Space or Return opens it, and VoiceOver presents it as a button.
final class NavigationRowView: ClickHoverStackView {
    var activate: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        focusRingType = .exterior
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { !isHiddenOrHasHiddenAncestor }
    override var focusRingMaskBounds: NSRect { bounds }

    /// Drawn inside the row: the row's layer clips to its rounded corners.
    override func drawFocusRingMask() {
        let radius = TableGroupView.cardCornerRadius - TableGroupView.borderWidth - 2
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: radius, yRadius: radius).fill()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
            // Return, Space, keypad Enter. A held key opens the page once, not again on each repeat.
            case 36, 49, 76: if !event.isARepeat { activate?() }
            default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        activate?()
        return true
    }
}

class ClickHoverStackView: NSStackView {
    var onClick: EventClosure?
    var onMouseEntered: EventClosure?
    var onMouseExited: EventClosure?
    // Background box shown on hover; a non-arranged subview pinned behind the row's content.
    var hoverBackground: NSBox?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove only our own tracking area so AppKit-managed ones (e.g. tooltip) survive.
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let newTrackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(newTrackingArea)
        hoverTrackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        // let subviews handle the event first
        super.mouseEntered(with: event)
        onMouseEntered?(event, self)
    }

    override func mouseExited(with event: NSEvent) {
        // let subviews handle the event first
        super.mouseExited(with: event)
        onMouseExited?(event, self)
    }

    override func mouseDown(with event: NSEvent) {
        // let subviews handle the event first
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        // let subviews handle the event first
        super.mouseUp(with: event)
        // macOS convention: a click activates on mouse-up over the same view (so dragging
        // out before release cancels the click, matching NSButton behavior).
        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            onClick?(event, self)
        }
    }
}
