// Draws CmdTab's icons: resources/icons/app/app.png and resources/icons/menubar/menubar-{0,1,2}.pdf.
// Usage: swift scripts/assets/make_icons.swift <output folder>, then copy the files into place.
import AppKit
import CoreText

let out = CommandLine.arguments[1]

// MARK: - the ⌘ glyph as a vector path, centered on the origin, scaled to `height`
func commandGlyph(height: CGFloat, weight: NSFont.Weight) -> CGPath {
    let font = NSFont.systemFont(ofSize: 100, weight: weight) as CTFont
    var chars: [UniChar] = Array("\u{2318}".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    precondition(CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count), "font has no ⌘")
    let path = CTFontCreatePathForGlyph(font, glyphs[0], nil)!
    let box = path.boundingBoxOfPath
    let scale = height / box.height
    var t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -box.midX, y: -box.midY)
    return path.copy(using: &t)!
}

func roundedSquare(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

let blueTop = CGColor(red: 0.30, green: 0.56, blue: 1.00, alpha: 1)
let blueBottom = CGColor(red: 0.10, green: 0.27, blue: 0.86, alpha: 1)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func blueGradient(_ ctx: CGContext, in rect: CGRect) {
    let g = CGGradient(colorsSpace: space, colors: [blueTop, blueBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
}

// MARK: - app icon, 1024px, on Apple's macOS icon grid (824px body, 100px margin)
func appIcon() {
    let size = 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = roundedSquare(body, radius: 185)
    // drop shadow under the body
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.30))
    ctx.addPath(bodyPath); ctx.setFillColor(blueBottom); ctx.fillPath()
    ctx.restoreGState()
    // body gradient
    ctx.saveGState(); ctx.addPath(bodyPath); ctx.clip(); blueGradient(ctx, in: body)
    // faint window shapes behind the key: the switching motif
    for window in [CGRect(x: 160, y: 520, width: 340, height: 260), CGRect(x: 524, y: 244, width: 340, height: 260)] {
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.13))
        ctx.addPath(roundedSquare(window, radius: 36)); ctx.fillPath()
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.30))
        for i in 0..<3 {
            ctx.fillEllipse(in: CGRect(x: window.minX + 30 + CGFloat(i) * 34, y: window.maxY - 50, width: 22, height: 22))
        }
    }
    ctx.restoreGState()
    // keycap: bevel underneath, face on top
    let face = CGRect(x: 282, y: 300, width: 460, height: 440)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: CGColor(red: 0.02, green: 0.08, blue: 0.35, alpha: 0.45))
    ctx.addPath(roundedSquare(face.offsetBy(dx: 0, dy: -26), radius: 96))
    ctx.setFillColor(CGColor(red: 0.78, green: 0.83, blue: 0.93, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(roundedSquare(face, radius: 96)); ctx.clip()
    let faceGradient = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 1), CGColor(red: 0.92, green: 0.95, blue: 1, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(faceGradient, start: CGPoint(x: 0, y: face.maxY), end: CGPoint(x: 0, y: face.minY), options: [])
    ctx.restoreGState()
    // ⌘ on the key face
    let glyph = commandGlyph(height: 250, weight: .bold)
    ctx.saveGState()
    ctx.translateBy(x: face.midX, y: face.midY)
    ctx.addPath(glyph); ctx.clip()
    blueGradient(ctx, in: CGRect(x: -125, y: -125, width: 250, height: 250))
    ctx.restoreGState()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/app.png"))
}

// MARK: - menubar icons, 22pt vector PDFs
func pdf(_ name: String, draw: (CGContext) -> Void) {
    var box = CGRect(x: 0, y: 0, width: 22, height: 22)
    let ctx = CGContext(URL(fileURLWithPath: "\(out)/\(name).pdf") as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF()
}

let key = CGRect(x: 2.5, y: 2.5, width: 17, height: 17)
let keyRadius: CGFloat = 4.5

// outlined: template, keycap outline with ⌘
pdf("menubar-0") { ctx in
    ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    ctx.setLineWidth(1.5)
    ctx.addPath(roundedSquare(key.insetBy(dx: 0.75, dy: 0.75), radius: keyRadius - 0.75)); ctx.strokePath()
    ctx.translateBy(x: 11, y: 11); ctx.addPath(commandGlyph(height: 9, weight: .semibold)); ctx.fillPath()
}
// filled: template, solid keycap with ⌘ cut out
pdf("menubar-1") { ctx in
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    var move = CGAffineTransform(translationX: 11, y: 11)
    let glyph = commandGlyph(height: 9, weight: .semibold).copy(using: &move)!
    ctx.addPath(roundedSquare(key, radius: keyRadius).subtracting(glyph)); ctx.fillPath()
}
// colored: blue keycap with white ⌘
pdf("menubar-2") { ctx in
    ctx.saveGState(); ctx.addPath(roundedSquare(key, radius: keyRadius)); ctx.clip(); blueGradient(ctx, in: key); ctx.restoreGState()
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.translateBy(x: 11, y: 11); ctx.addPath(commandGlyph(height: 9, weight: .semibold)); ctx.fillPath()
}

appIcon()
print("done")
