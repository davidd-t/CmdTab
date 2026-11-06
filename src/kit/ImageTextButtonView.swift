import Cocoa

/// A style picker card: a small drawn glyph above its name, inside a rounded card. The selected card
/// gets an accent outline. An invisible radio button covers the card, so clicks, keyboard focus and
/// VoiceOver all work as one radio option.
class ImageTextButtonView: NSView {
    class ImageButton: NSButton {
        override var focusRingMaskBounds: NSRect { bounds }

        override func drawFocusRingMask() {
            NSBezierPath(roundedRect: bounds, xRadius: ImageTextButtonView.cornerRadius, yRadius: ImageTextButtonView.cornerRadius).fill()
        }

        // The card draws itself; the button only takes clicks and focus.
        override func draw(_ dirtyRect: NSRect) {}

        override func mouseDown(with event: NSEvent) {
            let parent = superview as? ImageTextButtonView
            parent?.isPressed = true
            parent?.updateStyle()
            // NSButton.mouseDown blocks until the click is released or canceled.
            super.mouseDown(with: event)
            parent?.isPressed = false
            parent?.updateStyle()
        }
    }

    /// Clicks on the label fall through to the button underneath it.
    class ClickableLabel: NSTextField {
        override var mouseDownCanMoveWindow: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    /// Draws the style's glyph: three window thumbnails, three app icons, or two title lines.
    class GlyphView: NSView {
        let kind: String

        init(kind: String) {
            self.kind = kind
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            let midX = bounds.midX, midY = bounds.midY
            func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
                color.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            }
            switch kind {
                case "app_icons":
                    let side = CGFloat(15), gap = CGFloat(5)
                    let colors: [NSColor] = [.systemOrange, .systemGreen, .systemBlue]
                    let startX = midX - (3 * side + 2 * gap) / 2
                    for (i, color) in colors.enumerated() {
                        rounded(NSRect(x: startX + CGFloat(i) * (side + gap), y: midY - side / 2, width: side, height: side), 4, color)
                    }
                case "titles":
                    let color = NSColor.secondaryLabelColor.withAlphaComponent(0.55)
                    rounded(NSRect(x: midX - 22, y: midY + 1.5, width: 44, height: 4), 2, color)
                    rounded(NSRect(x: midX - 16, y: midY - 5.5, width: 32, height: 4), 2, color)
                default:
                    let w = CGFloat(22), h = CGFloat(14), gap = CGFloat(5)
                    let startX = midX - (3 * w + 2 * gap) / 2
                    for i in 0..<3 {
                        let rect = NSRect(x: startX + CGFloat(i) * (w + gap), y: midY - h / 2, width: w, height: h)
                        rounded(rect, 2.5, NSColor.systemBlue.withAlphaComponent(0.42))
                        // a lighter title bar across the top of each thumbnail
                        rounded(NSRect(x: rect.minX, y: rect.maxY - 4, width: w, height: 4), 2, NSColor.white.withAlphaComponent(0.35))
                    }
            }
        }
    }

    static let cornerRadius = CGFloat(9)
    static let cardHeight = CGFloat(70)

    var onClick: ActionClosure?
    var button: NSButton!
    var label: NSTextField!
    fileprivate(set) var isPressed = false
    private var windowObservers = [NSObjectProtocol]()

    var state: NSControl.StateValue = .off {
        didSet {
            button.state = state
            updateStyle()
        }
    }

    init(title: String, rawName: String, image: WidthHeightImage, state: NSControl.StateValue = .off) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = ImageTextButtonView.cornerRadius

        let glyph = GlyphView(kind: image.name)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        label = ClickableLabel(labelWithString: title)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        button = ImageButton(radioButtonWithTitle: "", target: nil, action: nil)
        button.imagePosition = .noImage
        button.focusRingType = .default
        button.translatesAutoresizingMaskIntoConstraints = false
        button.identifier = NSUserInterfaceItemIdentifier(rawName)
        // [weak self]: `onAction` is an associated object the button retains, so a strong capture
        // closes a cycle that outlives the Settings window.
        button.onAction = { [weak self] control in
            guard let self else { return }
            self.state = .on
            self.onClick?(control)
        }
        addSubview(button)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: ImageTextButtonView.cardHeight),
            glyph.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor),
            glyph.trailingAnchor.constraint(equalTo: trailingAnchor),
            glyph.heightAnchor.constraint(equalToConstant: 24),
            label.topAnchor.constraint(equalTo: glyph.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        self.state = state
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers = observeWindowKeyChanges(replacing: windowObservers) { [weak self] in self?.updateStyle() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyle()
    }

    func updateStyle() {
        let isSelected = button.state == .on
        let isKey = window?.isKeyWindow ?? false
        let accent: NSColor = isKey ? .controlAccentColor : .unemphasizedSelectedContentBackgroundColor
        withDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = (isSelected ? accent : NSColor.separatorColor).cgColor
        }
        layer?.borderWidth = isSelected ? 2 : 1
        alphaValue = isPressed ? 0.7 : 1.0
    }
}
