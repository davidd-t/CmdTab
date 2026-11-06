import Cocoa

/// The group on an exception's page: Hide in the switcher (with the window-title patterns when
/// that option is chosen), Turn off CmdTab's shortcuts, and the Bundle ID.
class ExceptionEditorView: NSView {
    private var entry: ExceptionEntry = ExceptionEntry(bundleIdentifier: "", hide: .none, ignore: .none, windowTitleContains: nil)
    private var onChange: ((ExceptionEntry) -> Void)?

    private let bundleIdField = NSTextField(string: "")
    private let hideDropdown = PopupButtonLikeSystemSettings()
    private let ignoreDropdown = PopupButtonLikeSystemSettings()
    private var patternsRow: NSView?
    private var patternsListStack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func bind(to entry: ExceptionEntry, onChange: @escaping (ExceptionEntry) -> Void) {
        self.entry = entry
        self.onChange = onChange
        refreshFromEntry()
    }

    private func setupLayout() {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.distribution = .fill
        rows.translatesAutoresizingMaskIntoConstraints = false

        let hideRow = makeHideRow()
        let patternsRow = makePatternsRow()
        let ignoreRow = makeIgnoreRow()
        let bundleRow = makeBundleIdRow()
        self.patternsRow = patternsRow

        addToGroup(rows, view: hideRow, addSeparator: false)
        rows.addArrangedSubview(patternsRow)
        patternsRow.leadingAnchor.constraint(equalTo: rows.leadingAnchor).isActive = true
        patternsRow.trailingAnchor.constraint(equalTo: rows.trailingAnchor).isActive = true
        addToGroup(rows, view: ignoreRow, addSeparator: true)
        addToGroup(rows, view: bundleRow, addSeparator: true)

        // The card is a background sibling (not the rows' container) so the stack drives its size.
        let card = TableGroupView.makeCard()
        addSubview(card)
        addSubview(rows)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func addToGroup(_ group: NSStackView, view: NSView, addSeparator: Bool) {
        if addSeparator {
            let sep = makeSeparator()
            group.addArrangedSubview(sep)
            sep.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: TableGroupView.rowHorizontalPadding).isActive = true
            sep.trailingAnchor.constraint(equalTo: group.trailingAnchor, constant: -TableGroupView.rowHorizontalPadding).isActive = true
        }
        group.addArrangedSubview(view)
        view.leadingAnchor.constraint(equalTo: group.leadingAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: group.trailingAnchor).isActive = true
    }

    private func makeSeparator() -> NSView {
        let sep = NSBox()
        sep.boxType = .custom
        sep.borderWidth = 0
        sep.fillColor = TableGroupView.rowSeparatorColor
        sep.titlePosition = .noTitle
        sep.contentViewMargins = .zero
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    private func makeBundleIdRow() -> NSView {
        let label = makeRowLabel(ExceptionsTab.labelBundleId)
        bundleIdField.translatesAutoresizingMaskIntoConstraints = false
        bundleIdField.placeholderString = NSLocalizedString("e.g. com.example.app", comment: "")
        bundleIdField.cell?.sendsActionOnEndEditing = true
        bundleIdField.target = self
        bundleIdField.action = #selector(bundleIdChanged(_:))
        bundleIdField.lineBreakMode = .byTruncatingHead
        bundleIdField.usesSingleLineMode = true
        bundleIdField.setAccessibilityLabel(ExceptionsTab.labelBundleId)
        return makeRow(label: label, control: bundleIdField, controlMinWidth: 240)
    }

    private func makeHideRow() -> NSView {
        let label = makeRowLabel(ExceptionsTab.labelHide)
        hideDropdown.translatesAutoresizingMaskIntoConstraints = false
        hideDropdown.removeAllItems()
        // One title per `ExceptionHidePreference` case, in the same order.
        hideDropdown.addItems(withTitles: ExceptionsTab.hideOptionTitles)
        hideDropdown.target = self
        hideDropdown.action = #selector(hideChanged(_:))
        hideDropdown.setAccessibilityLabel(ExceptionsTab.labelHide)
        return makeRow(label: label, control: hideDropdown)
    }

    private func makeIgnoreRow() -> NSView {
        let label = makeRowLabel(ExceptionsTab.labelIgnore)
        ignoreDropdown.translatesAutoresizingMaskIntoConstraints = false
        ignoreDropdown.removeAllItems()
        // One title per `ExceptionIgnorePreference` case, in the same order.
        ignoreDropdown.addItems(withTitles: ExceptionsTab.ignoreOptionTitles)
        ignoreDropdown.target = self
        ignoreDropdown.action = #selector(ignoreChanged(_:))
        ignoreDropdown.setAccessibilityLabel(ExceptionsTab.labelIgnore)
        return makeRow(label: label, control: ignoreDropdown)
    }

    private func makePatternsRow() -> NSView {
        patternsListStack.orientation = .vertical
        patternsListStack.alignment = .leading
        patternsListStack.spacing = 4
        patternsListStack.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(title: ExceptionsTab.labelAddPattern, target: self, action: #selector(addPatternTapped))
        addButton.bezelStyle = .recessed
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.image = NSImage.fromSymbol(.plus, pointSize: 11)
        addButton.imagePosition = .imageLeading

        let column = NSStackView(views: [patternsListStack, addButton])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false
        // Indented under "Hide in the switcher" to show they belong to it.
        column.edgeInsets = NSEdgeInsets(top: 0, left: TableGroupView.rowHorizontalPadding + 20, bottom: 12, right: TableGroupView.rowHorizontalPadding)
        return column
    }

    private func rebuildPatternsList() {
        patternsListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let initial = entry.windowTitleContains ?? []
        if initial.isEmpty {
            patternsListStack.addArrangedSubview(makePatternFieldRow(initial: ""))
        } else {
            for p in initial {
                patternsListStack.addArrangedSubview(makePatternFieldRow(initial: p))
            }
        }
    }

    private func makePatternFieldRow(initial: String) -> NSView {
        let field = NSTextField(string: initial)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = NSLocalizedString("e.g. Debug", comment: "")
        field.delegate = self
        field.usesSingleLineMode = true
        field.setAccessibilityLabel(NSLocalizedString("Window title contains", comment: ""))
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

        let removeButton = NSButton()
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.bezelStyle = .circular
        removeButton.isBordered = false
        removeButton.image = NSImage.fromSymbol(.minusCircleFill, pointSize: 14)
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.imagePosition = .imageOnly
        removeButton.target = self
        removeButton.action = #selector(removePatternTapped(_:))
        removeButton.setAccessibilityLabel(NSLocalizedString("Remove pattern", comment: ""))
        removeButton.widthAnchor.constraint(equalToConstant: 18).isActive = true
        removeButton.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let row = NSStackView(views: [field, removeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeRow(label: NSTextField, control: NSView, controlMinWidth: CGFloat = 0) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = TableGroupView.rowColumnGap
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.edgeInsets = NSEdgeInsets(top: 9, left: TableGroupView.rowHorizontalPadding, bottom: 9, right: TableGroupView.rowHorizontalPadding)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: TableGroupView.rowMinHeight).isActive = true
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        if controlMinWidth > 0 {
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: controlMinWidth).isActive = true
        }
        return row
    }

    private func makeRowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private func refreshFromEntry() {
        bundleIdField.stringValue = entry.bundleIdentifier
        if let hideIndex = ExceptionHidePreference.allCases.firstIndex(of: entry.hide), hideIndex < hideDropdown.numberOfItems {
            hideDropdown.selectItem(at: hideIndex)
        }
        if let ignoreIndex = ExceptionIgnorePreference.allCases.firstIndex(of: entry.ignore), ignoreIndex < ignoreDropdown.numberOfItems {
            ignoreDropdown.selectItem(at: ignoreIndex)
        }
        rebuildPatternsList()
        updatePatternsVisibility()
    }

    @objc private func bundleIdChanged(_ sender: NSTextField) {
        guard sender.stringValue != entry.bundleIdentifier else { return }
        entry.bundleIdentifier = sender.stringValue
        emitChange()
    }

    @objc private func hideChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        if i >= 0 && i < ExceptionHidePreference.allCases.count {
            entry.hide = ExceptionHidePreference.allCases[i]
            updatePatternsVisibility()
            emitChange()
        }
    }

    @objc private func ignoreChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        if i >= 0 && i < ExceptionIgnorePreference.allCases.count {
            entry.ignore = ExceptionIgnorePreference.allCases[i]
            emitChange()
        }
    }

    @objc private func addPatternTapped() {
        let row = makePatternFieldRow(initial: "")
        patternsListStack.addArrangedSubview(row)
        if let stack = row as? NSStackView, let field = stack.arrangedSubviews.first as? NSTextField {
            field.window?.makeFirstResponder(field)
        }
        commitPatterns()
    }

    @objc private func removePatternTapped(_ sender: NSButton) {
        var view: NSView? = sender
        while let v = view, !(v is NSStackView && v.superview === patternsListStack) {
            view = v.superview
        }
        if let row = view {
            patternsListStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        if patternsListStack.arrangedSubviews.isEmpty {
            patternsListStack.addArrangedSubview(makePatternFieldRow(initial: ""))
        }
        commitPatterns()
    }

    private func commitPatterns() {
        let patterns = patternsListStack.arrangedSubviews.compactMap { row -> String? in
            guard let stack = row as? NSStackView, let field = stack.arrangedSubviews.first as? NSTextField else { return nil }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        entry.windowTitleContains = patterns.isEmpty ? nil : patterns
        emitChange()
    }

    private func updatePatternsVisibility() {
        patternsRow?.isHidden = entry.hide != .windowTitleContains
    }

    private func emitChange() {
        onChange?(entry)
    }
}

extension ExceptionEditorView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        // Only pattern fields use this delegate; the Bundle ID field uses target/action.
        if field !== bundleIdField, isPatternField(field) {
            commitPatterns()
        }
    }

    private func isPatternField(_ field: NSTextField) -> Bool {
        var view: NSView? = field
        while let v = view {
            if v === patternsListStack { return true }
            view = v.superview
        }
        return false
    }
}
